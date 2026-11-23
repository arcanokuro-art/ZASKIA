# ZASKIA

Aplicación Android de inteligencia artificial local, desarrollada con Flutter por Zaskar Startup.

Estado: prototipo de interfaz. Los motores de IA aún no están integrados.


## Linux Debian

Piloto Debian 12+ amd64, paquete .deb y motor de texto GGUF por CPU incluido.
Instalación y requisitos: [guía Linux](packaging/linux/README.md).
El flujo `linux-deb.yml` compila y prueba dentro de Debian 12 y publica el instalador en Releases.

## Configuración modular (0.13.0)

- `lib/settings`: preferencias persistentes, categorías, buscador y perfiles.
- `lib/localization`: español por defecto; inglés, chino simplificado, coreano, japonés y francés.
- `lib/storage`: carpetas de modelos y respaldos locales de chats/adjuntos/ajustes.
- `lib/diagnostics`: información del equipo y registro sin contenido de conversaciones.
- `lib/updates`: consulta de Releases y descarga externa; instalación manual.
- `lib/runtime`: aplica hilos, contexto, temperatura y límite de respuesta a los motores.

Los respaldos programados funcionan mientras la app está abierta. Los agentes y
la ejecución de comandos todavía no están implementados y no tienen permisos ficticios.
Las copias `.zaskia` se importan como conversaciones adicionales y conservan adjuntos.
Los modelos no se incluyen. Se limita cada respaldo a 64 MB descomprimidos y 32 MB de adjuntos.
