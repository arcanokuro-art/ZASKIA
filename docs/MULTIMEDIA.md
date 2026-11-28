# ZASKIA 0.15 — descargas, conversaciones y estudio multimedia

## Qué ejecuta esta versión

| Función | Motor | Dónde se ejecuta |
| --- | --- | --- |
| Texto GGUF | llama.cpp incluido | Linux x86-64 / Android ARM64, CPU |
| Texto externo | Ollama | Equipo donde esté Ollama |
| Imagen y edición de imagen | ComfyUI | Equipo donde esté ComfyUI |
| Síntesis y transcripción de voz | LocalAI o servidor con API compatible | Equipo donde esté el servidor de voz |
| Música y video | Flujos API de ComfyUI | Equipo donde esté ComfyUI y sus modelos |

Los adaptadores multimedia están implementados; los binarios de ComfyUI/LocalAI y sus pesos **no vienen dentro del APK ni del .deb**. No se descarga ni ejecuta código de nodos automáticamente. La capacidad de un modelo, los formatos admitidos, el consumo de memoria y la aceleración dependen del motor instalado. Descargar un archivo no significa que el motor integrado pueda ejecutarlo.

## Descargas

Abre **Descargas** desde el menú. La cola se guarda en disco. Al volver a abrir ZASKIA, las tareas pendientes aparecen pausadas: puedes reanudarlas sin empezar de cero si el servidor admite rangos. Si no los admite, la descarga vuelve a empezar de forma segura. Cancelar elimina el parcial; pausar lo conserva. Si se pierde la conexión, reanudar conserva los bytes descargados. Un error de SHA-256 elimina el parcial corrupto.

Hugging Face permite escoger pesos y archivos auxiliares públicos. La revisión se fija al commit publicado en su API. Se comprueba el tamaño y, cuando el catálogo publica `lfs.sha256`, también SHA-256. Los GGUF llevan comprobación de cabecera. No se admiten aún repositorios privados o sujetos a autorización. Los modelos multipartes requieren descargar todas sus partes y un motor compatible; el motor integrado mantiene su soporte de GGUF de texto individuales. Los pesos de motores externos se colocan en la carpeta que esos motores esperan, no se instalan automáticamente en ellos.

El sistema operativo puede terminar la aplicación al trabajar en segundo plano: no es un servicio de descarga permanente. El parcial persistido permite continuar después. La política de red bloquea las nuevas conexiones. La opción de no trabajar en segundo plano pausa las descargas en vez de destruirlas.

## Configuración de ejecución

En **Configuración de ejecución** están los hilos, contexto, longitud máxima, temperatura, perfiles, límite de turnos, tiempo límite y estadísticas. Confirma los campos numéricos con Enter. Aplicar libera el modelo; la próxima petición lo carga con los ajustes actuales. Los parámetros que pertenecen al servidor externo, como su GPU/VRAM, se configuran allí.

El presupuesto de contexto utiliza una estimación conservadora por bytes, no el tokenizador exacto de todos los modelos. Se conservan turnos completos recientes y las instrucciones; si el último mensaje no cabe, se pide reducirlo o ampliar contexto. No se promete memoria ilimitada.

## Conversaciones

- Markdown seleccionable y copia de respuesta.
- Editar o regenerar conserva una versión previa de la conversación. **Versiones de conversación** permite recuperarla.
- Buscar texto en la conversación actual.
- Exportar JSON (incluye versiones) y Markdown a una carpeta elegida.
- Importar JSON como conversación nueva; las rutas de adjuntos del archivo importado se descartan. Para transportar adjuntos utiliza el respaldo `.zaskia`.
- Indicadores de modelo, estado y tiempo total. Detener conserva el texto generado hasta ese momento.

No hay publicación ni enlace para compartir conversaciones.

## Imagen

1. Instala y ejecuta ComfyUI en el equipo que hará la inferencia. Usa una versión actual y un servidor dedicado a ZASKIA si vas a cancelar trabajos.
2. Abre **Estudio multimedia → Imagen**, escribe la dirección de ese motor y comprueba conexión.
3. Elige un checkpoint compatible con el flujo básico CLIP/VAE. Describe la imagen, configura dimensiones, semilla y pasos y genera.
4. Para editar, selecciona una imagen de entrada. Se envía a `/upload/image`, se codifica con VAE y se aplica la intensidad de edición.
5. Para modelos con otra arquitectura (por ejemplo FLUX o Qwen), importa un flujo **Exportar (API)** válido y compatible con los nodos/pesos de tu servidor.

En Android, `127.0.0.1` apunta a la tablet, **no al PC**. Si ComfyUI corre en tu PC, configura la IP local de ese PC y el puerto correspondiente. No hace falta un servicio comercial en la nube. Permitir conexiones de red en ZASKIA también es necesario para hablar con un servidor de tu red local.

## Música y video

Elige la modalidad e importa un flujo API de ComfyUI que hayas validado con el modelo deseado. Puede contener nodos de música, audio o video de tu instalación. ZASKIA valida que los tipos de nodos existan antes de enviarlo; el servidor valida entradas y pesos al aceptar el trabajo. El flujo debe incluir un nodo de guardado con salidas `audio`, `videos`, `gifs` o `images` en su historial.

Variables admitidas dentro de los valores del JSON:

| Variable | Tipo al ocupar todo el valor |
| --- | --- |
| `{{prompt}}`, `{{negative_prompt}}`, `{{input_image}}` | Texto |
| `{{seed}}`, `{{width}}`, `{{height}}`, `{{steps}}` | Entero |
| `{{cfg}}` | Número |

También pueden usarse como parte de un texto. No se sustituyen IDs de nodos ni se ejecuta código del archivo JSON. El flujo predeterminado es para imagen; música y video necesitan un flujo de su modelo, no se presenta un flujo de imagen como si generara música. Un flujo de canciones con letra o voces requiere un modelo capaz de hacerlo; esta integración no equivale a garantizar la calidad de Suno.

Se consulta `/history/{prompt_id}` hasta terminar (máximo 30 minutos). Un error, una interrupción, falta de nodos o ausencia de archivos no se marcan como éxito. Se guardan archivos completos con extensiones PNG/JPG/WEBP/GIF, WAV/MP3/FLAC/OGG y MP4/WEBM/MOV. Los formatos dependen del nodo de salida. Al cancelar se usa el ID del trabajo; se retira de la cola o se solicita interrumpirlo en el servidor. Si el servidor no responde, ZASKIA informa que se detuvo localmente y debes revisar su cola. Un cierre forzado del proceso puede dejar un trabajo activo en el servidor.

## Voz

Configura un servidor LocalAI o compatible con `/v1/models`, `/v1/audio/speech` y `/v1/audio/transcriptions`. Escribe el ID del modelo instalado de síntesis o transcripción y el nombre de voz que ese modelo soporte. **Generar** guarda WAV; **Transcribir audio** envía el archivo como multipart y guarda el texto. No se instala un modelo de voz dentro de ZASKIA ni se clona una voz automáticamente. Este piloto utiliza servidores sin autenticación; no pongas credenciales en la dirección.

## Galería

Cada trabajo guarda su descripción, parámetros, flujo de imagen/música/video y archivos en una carpeta local. Las imágenes se muestran en la aplicación; audio y video se abren con un reproductor del sistema. Puedes exportar la carpeta del trabajo y reutilizar la descripción/semilla o plantilla. Los flujos importados guardan una plantilla separada del flujo resuelto para poder cambiar la descripción al reutilizarlos. La calidad visual, musical y de voz requiere pruebas con tus modelos y tu hardware.

## Validación de desarrollo

Las pruebas automatizadas ejercitan servidores HTTP de prueba: rangos, corrupción SHA-256, persistencia de cola, variables tipadas, rechazo de nodos ausentes, envío y recuperación de archivos de las tres modalidades ComfyUI, síntesis y transcripción multipart, presupuesto de contexto e importación sin rutas externas. Esto verifica el cliente y el protocolo; no equivale a una prueba de calidad o rendimiento con pesos multimedia reales.

Referencias de protocolo:
- https://docs.comfy.org/development/comfyui-server/comms_routes
- https://localai.io/docs/models/capabilities/audio/
