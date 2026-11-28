"""Verify process groups and parent-death cleanup with our tiny local launcher."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('cc'), 'Linux C compiler required')
class ManagedLauncherTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix='zaskia-launcher-')
        cls.launcher = str(Path(cls.folder.name) / 'launcher')
        subprocess.run(['cc', '-O2', '-Wall', '-Wextra', '-Werror',
                        'packaging/linux/managed-engine.c', '-o', cls.launcher], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def test_owns_its_process_group(self):
        process = subprocess.Popen([self.launcher, '/bin/sleep', '5'])
        try:
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline and os.getpgid(process.pid) != process.pid:
                time.sleep(.01)
            self.assertEqual(os.getpgid(process.pid), process.pid)
            os.killpg(process.pid, signal.SIGTERM)
            self.assertEqual(process.wait(timeout=2), -signal.SIGTERM)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_exits_after_its_parent_dies(self):
        script = ('import subprocess,time; p=subprocess.Popen([' + repr(self.launcher)
                  + ',"/bin/sleep","5"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);'
                    'print(p.pid,flush=True);time.sleep(.2)')
        parent = subprocess.Popen([sys.executable, '-c', script], stdout=subprocess.PIPE, text=True)
        child = int(parent.stdout.readline().strip())
        parent.wait(timeout=3)
        parent.stdout.close()
        deadline = time.monotonic() + 2
        alive = True
        while time.monotonic() < deadline:
            try:
                state = Path(f'/proc/{child}/stat').read_text().split(') ')[1].split()[0]
                alive = state not in ('Z', 'X')
            except FileNotFoundError:
                alive = False
            if not alive:
                break
            time.sleep(.02)
        if alive:
            os.kill(child, signal.SIGKILL)
        self.assertFalse(alive, 'Managed engine outlived its application')
