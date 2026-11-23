import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('configure_cpu', 'tool/android/configure_cpu.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AndroidCpuTests(unittest.TestCase):
    def fixture(self, root):
        android = Path(root) / 'android'
        android.mkdir()
        cmake = android / 'CMakeLists.txt'
        cmake.write_text('set(CMAKE_C_FLAGS "-march=armv8-a+crc")\nset(CMAKE_CXX_FLAGS "-march=armv8-a+crc")\nadd_subdirectory(src/main/cpp/llama.cpp)\n')
        gradle = android / 'build.gradle.kts'
        gradle.write_text('arguments += "-DGGML_DOTPROD=ON"\n')
        return cmake, gradle

    def test_portable_flags_and_idempotence(self):
        with tempfile.TemporaryDirectory() as root:
            cmake, gradle = self.fixture(root)
            module.configure(root)
            self.assertNotIn('armv8-a+crc', cmake.read_text())
            self.assertIn('GGML_NATIVE OFF', cmake.read_text())
            self.assertIn('GGML_CPU_ARM_ARCH "armv8-a"', cmake.read_text())
            self.assertNotIn('-DGGML_DOTPROD=ON', gradle.read_text())
            before = cmake.read_text()
            module.configure(root)
            self.assertEqual(before, cmake.read_text())

    def test_unknown_plugin_is_rejected_before_changes(self):
        with tempfile.TemporaryDirectory() as root:
            cmake, gradle = self.fixture(root)
            cmake.write_text('upstream changed')
            before = gradle.read_text()
            with self.assertRaises(ValueError):
                module.configure(root)
            self.assertEqual(before, gradle.read_text())
