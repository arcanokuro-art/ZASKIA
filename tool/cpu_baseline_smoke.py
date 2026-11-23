"""Exercise real inference under an emulated x86-64 CPU without AVX/SSE4.2."""
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
command = ['qemu-x86_64', '-cpu', 'qemu64,-avx,-avx2,-sse4.2,-sse4.1',
           '/usr/lib/zaskia/llama-server', '--model', sys.argv[1], '--host', '127.0.0.1',
           '--port', str(port), '--ctx-size', '512', '--threads', '1', '--n-gpu-layers', '0',
           '--parallel', '1', '--no-webui']
with open('build/cpu-baseline.log', 'w+') as log:
    process = subprocess.Popen(command, cwd='/usr/lib/zaskia', stdout=log, stderr=log)
    try:
        endpoint = 'http://127.0.0.1:' + str(port)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Baseline server exited: ' + str(process.returncode))
            try:
                with urllib.request.urlopen(endpoint + '/health', timeout=2) as response:
                    if response.status == 200:
                        break
            except (OSError, urllib.error.URLError):
                time.sleep(.2)
        else:
            raise RuntimeError('Baseline model load timed out')
        body = json.dumps({'messages': [{'role': 'user', 'content': 'Once upon a time'}],
                           'max_tokens': 8, 'temperature': 0, 'stream': False}).encode()
        request = urllib.request.Request(endpoint + '/v1/chat/completions', data=body,
                                         headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=60) as response:
            result = json.load(response)
        assert result['usage']['completion_tokens'] > 0
        with open('/proc/' + str(process.pid) + '/maps') as maps:
            loaded = maps.read()
        assert 'libggml-cpu-x64.so' in loaded, loaded[-5000:]
        print('Baseline CPU inference passed without AVX or SSE4.2.')
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
