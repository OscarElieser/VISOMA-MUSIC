# VÍSOMA MUSIC — prototipo Flutter 0.5

Reproductor personal de audio y video con biblioteca local y entrada online para archivos HTTPS **directos y autorizados**. No descarga ni extrae contenido de YouTube o Spotify. Una URL de la página de un video no es una URL directa de su archivo multimedia.

## Ejecutar en Android

1. Instala Flutter y Android Studio y configura un Android SDK.
2. Descomprime el ZIP, abre PowerShell dentro de `visoma_music` y ejecuta `powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1`.
3. El script genera la carpeta Android, añade el permiso de internet y el nombre de la app, instala dependencias, analiza el código, ejecuta las pruebas y construye `build/app/outputs/flutter-apk/app-debug.apk`.
4. Para depurar con un teléfono conectado usa `flutter run` dentro de la misma carpeta.

## Funciones disponibles en el código

- Importa archivos con el selector del sistema y copia el contenido al almacenamiento privado de la app. La biblioteca local permanece tras cerrar y abrir la app.
- Reproduce audio y video locales; incorpora archivos HTTPS directos de fuentes autorizadas para escuchar online.
- Conserva fuentes online y favoritos en un índice JSON local; incluye búsqueda, eliminar elementos de la biblioteca y pausa/reanudación.
- Modo viaje indica cuántos elementos son locales y cuántos requieren conexión.
- Interfaz propia en tonos carbón, coral y violeta: Inicio, Biblioteca con filtros, Modo viaje y reproductor compacto con video integrado.
- Listas personales y cola de reproducción con anterior/siguiente; barra de progreso para buscar dentro de audio y video.
- Letras `.lrc` sincronizadas y `.txt` sin marcas de tiempo, vinculadas manualmente a cada canción. Tocar una línea sincronizada mueve la reproducción a ese instante.
- Descarga de archivos HTTPS **directos y autorizados** por Wi-Fi, con límite de 250 MB y verificación de respuesta multimedia. Guarda una copia local que aparece en Modo viaje.
- Comandos escritos de Vísoma que funcionan offline: reproducir una canción de la biblioteca, pausar, anterior, siguiente y cambiar de modo. El motor de comandos es local y basado en reglas; todavía no hay reconocimiento de voz ni modelo generativo.
- Importación de un catálogo propio en JSON desde HTTPS, con título, artista, álbum, género, tipo, enlace directo y declaración de derechos. Los elementos sin `downloadAllowed: true` no muestran botón de descarga. Consulta `docs/catalog.md`.
- El modo sin conexión bloquea contenido online. «Solo Wi-Fi» viene activado; consulta el tipo de conexión antes de reproducir y pausa si el dispositivo deja de indicar Wi-Fi.

## Límites actuales

Esto es un **prototipo fuente**, no un APK probado. Flutter no está instalado en el entorno en que se preparó; no se han podido ejecutar `flutter pub get`, análisis ni pruebas en Android. `setup_windows.ps1` crea y compila un APK de depuración en un equipo Windows que tenga Flutter y Android SDK.

La detección de Wi-Fi no mide el consumo real ni garantiza acceso a internet; algunas conexiones pueden cambiar de ruta antes de que llegue el evento. La selección de audio/video se basa inicialmente en la extensión y el códec se comprueba cuando se abre. La importación ocupa espacio adicional porque hace una copia privada. Las letras deben ser proporcionadas por el usuario. Faltan lectura automática de música ya guardada sin copiarla, subtítulos, asistente **por voz**, recomendaciones inteligentes, catálogo musical con licencia, controles de bloqueo y reproducción de audio en segundo plano. La reproducción de video depende del ciclo de vida de la pantalla.

El lector de catálogos interpreta la declaración de derechos publicada por el operador, pero no verifica contratos ni aporta canciones por sí solo. La descarga offline está limitada a URLs HTTPS directas que entreguen un tipo de audio/video reconocido; no acepta páginas de YouTube o servicios de streaming.

Las pruebas de parser incluidas en `test/` pueden ejecutarse con `flutter test` cuando Flutter esté instalado. No se ejecutaron aquí.

El diseño se integra directamente con las acciones existentes; no incluye fotografías ni copia componentes gráficos de otras aplicaciones. El emblema de pulso y órbitas está dibujado con código Flutter y puede ajustarse durante la revisión visual.
