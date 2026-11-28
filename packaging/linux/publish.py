"""Publish via the GitHub API without requiring a Debian gh package."""
import glob
import json
import os
import urllib.error
import urllib.request

repo = os.environ['GITHUB_REPOSITORY']
tag = os.environ['TAG']
version = tag.removeprefix('v')
headers = {'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
           'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
base = 'https://api.github.com/repos/' + repo

def request(url, data=None, method=None, content_type='application/json'):
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={**headers, 'Content-Type': content_type})
    with urllib.request.urlopen(req, timeout=120) as response:
        body = response.read()
        return json.loads(body) if body else None

try:
    release = request(base + '/releases/tags/' + tag)
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise
    try:
        release = request(base + '/releases', json.dumps({
            'tag_name': tag, 'target_commitish': os.environ['GITHUB_SHA'],
            'name': 'ZASKIA ' + tag, 'prerelease': True,
            'body': f'Piloto para Debian 12+ amd64. Incluye motor GGUF de texto por CPU, biblioteca y Hugging Face. Instalar con sudo apt install ./ZASKIA-{version}-linux-amd64.deb. Los modelos se descargan aparte.',
        }).encode())
    except urllib.error.HTTPError as conflict:
        if conflict.code != 422:
            raise
        release = request(base + '/releases/tags/' + tag)
body = release.get('body') or ''
if 'Debian' not in body:
    body += f'\n\nLinux Debian 12+ amd64: paquete .deb con motor de texto GGUF por CPU incluido. Instalar con `sudo apt install ./ZASKIA-{version}-linux-amd64.deb`. Los modelos se descargan aparte.'
    request(base + '/releases/' + str(release['id']), json.dumps({'body': body}).encode(), method='PATCH')
if 'Configuración modular' not in body:
    body += '\n\nConfiguración modular: apariencia, perfiles, rendimiento, memoria, permisos, cola de descargas, respaldos, diagnóstico y actualizaciones. Español predeterminado; inglés, chino simplificado, coreano, japonés y francés disponibles.'
    request(base + '/releases/' + str(release['id']), json.dumps({'body': body}).encode(), method='PATCH')
if 'Estudio multimedia' not in body:
    body += '\n\nEstudio multimedia: adaptadores ComfyUI (imagen, música y video) y voz LocalAI/compatible. Los motores y modelos multimedia se instalan por separado. Descargas reanudables y verificadas, controles de ejecución y conversaciones con versiones, Markdown e importación/exportación.'
    request(base + '/releases/' + str(release['id']), json.dumps({'body': body}).encode(), method='PATCH')
if 'Guía de inicio' not in body:
    body += '\n\nGuía de inicio, compatibilidad orientativa de modelos y gestor de motores. Linux permite instalar, iniciar y actualizar Ollama/ComfyUI; los pesos se descargan aparte. Android usa texto integrado o conexiones a otro equipo. Consulta docs/GETTING_STARTED.md en la rama de desarrollo.'
    request(base + '/releases/' + str(release['id']), json.dumps({'body': body}).encode(), method='PATCH')
for path in sorted(glob.glob('ZASKIA-*-linux-amd64.deb*')):
    name = os.path.basename(path)
    for asset in release.get('assets', []):
        if asset['name'] == name:
            request(asset['url'], method='DELETE')
    with open(path, 'rb') as file:
        request(release['upload_url'].split('{')[0] + '?name=' + name,
                file.read(), content_type='application/octet-stream')
    print('Published', name)
