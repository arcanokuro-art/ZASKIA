# ZASKIA

Aplicación Android de IA local de Zaskar Startup. La APK para ARM64 se publica desde la rama de desarrollo mediante GitHub Actions.

## Módulos

- `lib/app` contiene el tema y el punto de composición de Flutter.
- `lib/features/chat` contiene la conversación, el compositor y las vistas de adjuntos.
- `lib/features/models` contiene el motor de texto Qwen con llama.cpp.
- `lib/features/images` contiene la gestión de pesos y la generación de imágenes con FLUX.
- `platform/android` contiene el canal nativo y el script de compilación de stable-diffusion.cpp.
- `test` contiene las pruebas de Flutter.

## Modelos de imagen

En **☰ → Modelos de imagen**, importa los tres componentes de la variante destilada de FLUX.2 klein 4B:

1. [FLUX.2 klein 4B GGUF](https://huggingface.co/leejet/FLUX.2-klein-4B-GGUF), cuantización Q4.
2. [Qwen3 4B GGUF](https://huggingface.co/unsloth/Qwen3-4B-GGUF), cuantización Q4. Este es el codificador de imagen, separado del Qwen 1.7B del chat.
3. VAE de FLUX.2 (`flux2_ae.safetensors`), enlazado en la [guía de stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp/blob/5dcfa79801213f23e27b3e83617350ebb8ea93aa/docs/models/flux2.md).

Desde **+ → Crear imagen**, escribe la descripción. Para **Editar imagen**, adjunta una o dos referencias y describe el cambio. El motor experimental usa CPU, una salida de 512 × 512 y requiere 5 GiB de RAM disponible. Los pesos y las imágenes se procesan en el dispositivo.
