"""Keep the pinned Android CPU backend at the ARMv8-A ABI baseline."""
import json
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

MARKER = '# ZASKIA_ARMV8_BASELINE'

def configure(root):
    root = Path(root)
    cmake_path = root / 'android/CMakeLists.txt'
    gradle_path = root / 'android/build.gradle.kts'
    cmake = cmake_path.read_text()
    gradle = gradle_path.read_text()
    if MARKER in cmake:
        if 'armv8-a+crc' in cmake or '-DGGML_DOTPROD=ON' in gradle:
            raise ValueError('Inconsistent CPU baseline patch')
        return
    if cmake.count('-march=armv8-a+crc') != 2 or gradle.count('-DGGML_DOTPROD=ON') != 1:
        raise ValueError('Pinned plugin changed; review CPU flags before building')
    anchor = 'add_subdirectory(src/main/cpp/llama.cpp)'
    if cmake.count(anchor) != 1:
        raise ValueError('Unknown llama.cpp CMake entry point')
    cmake = cmake.replace('-march=armv8-a+crc', '-march=armv8-a')
    cmake = cmake.replace(anchor, '''# ZASKIA_ARMV8_BASELINE
set(GGML_NATIVE OFF CACHE BOOL "Portable Android CPU" FORCE)
set(GGML_CPU_ARM_ARCH "armv8-a" CACHE STRING "Android ARM64 baseline" FORCE)
set(GGML_DOTPROD OFF CACHE BOOL "No unconditional dot-product requirement" FORCE)
''' + anchor)
    gradle = gradle.replace('-DGGML_DOTPROD=ON', '-DGGML_DOTPROD=OFF')
    cmake_path.write_text(cmake)
    gradle_path.write_text(gradle)

if __name__ == '__main__':
    config = Path('.dart_tool/package_config.json').resolve()
    packages = json.loads(config.read_text())['packages']
    entry = next(p for p in packages if p['name'] == 'llama_flutter_android')
    uri = urlparse(urljoin(config.as_uri(), entry['rootUri']))
    if uri.scheme != 'file':
        raise ValueError('Expected a local plugin directory')
    configure(Path(unquote(uri.path)))
    print('Android CPU configured for ARMv8-A without mandatory CRC or dot-product.')
