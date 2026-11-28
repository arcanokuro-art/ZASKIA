# ZASKIA 0.16.1

Guía de primer inicio, compatibilidad orientativa y gestión de motores. [Guía de inicio y alcance de las instalaciones](docs/GETTING_STARTED.md).

Descargas reanudables, configuración de ejecución, conversaciones con versiones y estudio multimedia modular. [Guía y alcance real de los motores](docs/MULTIMEDIA.md).

Ejecutor modular de inteligencia artificial para Android ARM64 y Linux x86-64, desarrollado con Flutter por Zaskar Startup.

Incluye texto GGUF por CPU y adaptadores multimedia para motores instalados por separado.


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

## Hardware y rendimiento (0.14.0)

- `lib/hardware`: ABI del proceso, sensores Linux/Android y recomendaciones conservadoras.
- `lib/benchmark`: protocolo fijo, cancelación, mediciones e historial/exportación JSON.
- CPU integrada en Linux x86-64 y Android ARM64; no se declara soporte validado en otros sistemas.
- Las instalaciones nuevas adaptan hilos y contexto. Las existentes requieren aplicar la recomendación.
- Linux incorpora despacho de CPU x64/SSE4.2/AVX/AVX2 y una prueba de inferencia sin AVX bajo QEMU.
- El conteo de tokens proviene del backend cuando está disponible. Se guarda también texto Unicode
  por segundo de tiempo total, latencia al primer texto y estado de carga inicial.
- Los informes excluyen respuestas, conversaciones, memoria personal, rutas de modelos y URL de Ollama.
- La memoria disponible y sus estimaciones no garantizan que un modelo quepa; faltan pruebas físicas
  por cada fabricante. No se activa GPU/NPU en esta versión.

Android (0.14.1): `tool/android/configure_cpu.py` adapta la dependencia fijada a
ARMv8-A sin requisitos incondicionales CRC/dot-product. La configuración es
idempotente y falla si cambia la estructura del plugin. Esto no reemplaza las
pruebas físicas por fabricante, versión de Android y modelo.
