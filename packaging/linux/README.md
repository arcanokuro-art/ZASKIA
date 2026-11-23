ZASKIA para Debian — piloto 0.12.0

Requisitos: Debian 12 o posterior, escritorio gráfico, procesador x86-64
(Intel/AMD de 64 bits). Esta compilación utiliza CPU; no requiere CUDA.
No es un paquete ARM64 ni de 32 bits. La RAM necesaria depende del modelo.

Instalación desde la carpeta donde descargaste el archivo:
  sudo apt install ./ZASKIA-0.12.0-linux-amd64.deb

Abrir: menú de aplicaciones → ZASKIA, o ejecutar `zaskia` en una terminal.
Desinstalar: sudo apt remove zaskia
Actualizar: instalar el nuevo .deb con apt.

Biblioteca: importa un GGUF de texto o descárgalo desde Hugging Face y pulsa
Cargar. El motor llama.cpp está incluido. También se puede conectar Ollama
por HTTP. No se incluye ningún modelo ni se descarga uno automáticamente.
Los modelos, chats y ajustes se guardan en el directorio de datos de la
aplicación del usuario (XDG_DATA_HOME o ~/.local/share), fuera de /usr.

El bloqueo biométrico y la captura con cámara de Android no están habilitados
en este piloto Linux. Puedes adjuntar fotos y archivos desde el equipo.
Imágenes, música y video todavía no tienen un motor de generación integrado.

Motor: llama.cpp v1.0.0, commit b1b770d90d94cad9e9ea5b993bdbc383a522fb28,
MIT. Véanse llama.cpp-copyright y third-party-licenses en este directorio.
