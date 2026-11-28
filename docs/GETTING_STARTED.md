# ZASKIA 0.16 — primer inicio, compatibilidad y motores

## Primer inicio

La guía aparece cuando aún no se ha completado y también puede abrirse desde el menú o Ajustes → Guía de inicio. **Configurar después** permite entrar directamente al programa; no borra conversaciones ni cambia el motor previamente seleccionado.

1. Muestra sistema, arquitectura, núcleos y memoria observada. Aplicar la recomendación es opcional.
2. Sugiere un GGUF pequeño de texto según un presupuesto conservador. Las sugerencias iniciales son Qwen2.5 Instruct Q4_K_M de 0.5B, 1.5B y 3B, de los repositorios de Qwen. No son los únicos modelos compatibles ni una comparación de calidad con otros modelos.
3. Antes de descargar, consulta la revisión, tamaño y licencia reales publicados en Hugging Face. Pide confirmar la descarga. Las tareas usan la cola reanudable de ZASKIA y revisiones fijas.
4. Permite cargar un GGUF ya disponible o importar uno, y probar un saludo real mediante el motor integrado antes de ir al chat. Un error no se presenta como una respuesta exitosa.

No se instala ningún peso ni se inicia ninguna descarga al abrir la aplicación.

## Compatibilidad

La biblioteca incluye pesos externos (safetensors, ONNX, BIN, PT/PTH/model) además de GGUF. Que aparezcan en la biblioteca **no los hace ejecutables por llama.cpp**. La ficha muestra formato, motor necesario y estado de compatibilidad.

- GGUF incompleto, embeddings conocidos, modelos divididos o ABI no admitida: bloqueo de carga por el motor integrado.
- Arquitectura desconocida o memoria no observable: compatibilidad sin verificar.
- Modelo de texto reconocido: candidato, no garantía.
- Presión estimada sobre RAM libre: advertencia con confirmación antes de intentar cargar.

La estimación incluye tamaño de pesos, margen de ejecución y una aproximación amplia de contexto. No conoce el KV cache exacto de todas las arquitecturas ni garantiza evitar OOM. No se atribuyen capacidades de imagen a un GGUF de texto aunque su familia tenga una variante multimodal. La carga nativa vuelve a comprobar los bloqueos, además de la interfaz.

## Gestor de motores

### Motor integrado

llama.cpp forma parte de ZASKIA y se actualiza con su instalador. Android ARM64 y Debian x86-64 mantienen este modo de texto por CPU.

### Linux x86-64: instalaciones administradas

Requisitos: git, python3 con venv, zstd y util-linux (setsid). El .deb recomienda git, python3-venv y zstd. Si faltan en una instalación que omite recomendaciones, instálalos mediante el administrador de paquetes de tu sistema. Hace falta conexión para instalar o actualizar; las descargas pueden ocupar varios GiB.

- **Ollama:** consulta la versión estable oficial en GitHub, descarga el archivo Linux amd64 de esa publicación y exige su digest SHA-256 oficial antes de extraerlo. No ejecuta el instalador remoto con sudo ni registra un servicio del sistema.
- **ComfyUI:** consulta la versión estable oficial, resuelve su commit y trae ese commit a una carpeta nueva. Crea un venv privado, instala PyTorch CPU desde su índice CPU y las dependencias de ese commit, y comprueba `main.py --help`. No instala nodos personalizados automáticamente. Las dependencias transitivas de pip no están fijadas por ZASKIA; la compatibilidad con versiones futuras de estos motores requiere validación continua.
- La instalación activa se cambia solamente después de completar las comprobaciones. Una actualización fallida conserva la activa. **Volver a la versión anterior** intercambia los punteros de instalación; no borra pesos ni migra bases de datos. El espacio de entornos anteriores no se elimina automáticamente.
- **Iniciar** crea un proceso propio, ligado a la vida de la aplicación, en un puerto local libre. No ocupa ni detiene un servicio ajeno. Al estar listo guarda la dirección para Ollama o el estudio multimedia.
- **Detener** termina el grupo del proceso iniciado por ZASKIA. El lanzador Linux también solicita terminar el proceso si muere la aplicación. No se convierte en un servicio permanente en segundo plano.
- ComfyUI administrado utiliza CPU; Ollama gestiona sus propios dispositivos. No se promete velocidad de GPU, soporte físico de todas las CPUs ni inferencia multimedia sin pesos compatibles.
- **Instalar componente de modelo** copia de forma atómica un archivo de pesos a una categoría de modelos de la instalación administrada de ComfyUI. No sustituye archivos existentes. El usuario debe elegir la categoría que requiere el modelo y aportar todos sus componentes. La aplicación no puede deducir la arquitectura completa de un safetensors a partir de su extensión.

### Android y servidores externos

Android no instala procesos Python ni binarios Linux de escritorio. Permite usar el motor de texto incluido o comprobar y guardar conexiones de Ollama, ComfyUI y LocalAI/voz compatible en otro equipo. `127.0.0.1` es la tablet; para el PC se utiliza su dirección local. El gestor no puede iniciar o detener el sistema operativo de ese otro equipo.

La instalación administrada de LocalAI/voz queda pendiente: se conecta a un servidor previamente instalado. Este hito no implementa todos los motores existentes ni instala sus pesos automáticamente.

## Validación

Pruebas de clasificación y estimación de compatibilidad, sugerencias bajo memoria limitada, UI de configuración opcional, planes de instalación con ejecutor de prueba, conservación de instalación activa tras fallo y rollback. El lanzador C se compila con advertencias como errores. La CI también mantiene análisis, pruebas, empaquetado, instalación de Debian, inferencia GGUF real y prueba de CPU sin AVX.

Las pruebas del instalador ComfyUI simulan comandos: no equivalen a descargar todas las dependencias y ejecutar un modelo multimedia real. Se necesitan pruebas de instalación con las versiones que se vayan a distribuir y con el hardware final. La RAM y velocidad mostradas en la guía no sustituyen estas pruebas.

Referencias:
- https://github.com/ollama/ollama/releases
- https://github.com/Comfy-Org/ComfyUI/releases
- https://github.com/Comfy-Org/ComfyUI/blob/master/docs/installation.md
- https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF
