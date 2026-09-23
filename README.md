# VÍSOMA MUSIC — prototipo Flutter 0.3

Reproductor personal de audio y video con biblioteca local y entrada online para archivos HTTPS **directos y autorizados**. No descarga ni extrae contenido de YouTube o Spotify. Una URL de la página de un video no es una URL directa de su archivo multimedia.

## Ejecutar en Android

1. Instala Flutter y Android Studio.
2. Abre esta carpeta en una terminal y ejecuta `flutter create --platforms=android .` y `flutter pub get`.
3. En `android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>` y antes de `<application>`, añade `<uses-permission android:name="android.permission.INTERNET" />`.
4. Conecta un dispositivo Android y ejecuta `flutter run`.

## Funciones disponibles en el código

- Importa archivos con el selector del sistema y copia el contenido al almacenamiento privado de la app. La biblioteca local permanece tras cerrar y abrir la app.
- Reproduce audio y video locales; incorpora archivos HTTPS directos de fuentes autorizadas para escuchar online.
- Conserva fuentes online y favoritos en un índice JSON local; incluye búsqueda, eliminar elementos de la biblioteca y pausa/reanudación.
- Modo viaje indica cuántos elementos son locales y cuántos requieren conexión.
- Interfaz propia en tonos carbón, coral y violeta: Inicio, Biblioteca con filtros, Modo viaje y reproductor compacto con video integrado.
- El modo sin conexión bloquea contenido online. «Solo Wi-Fi» viene activado; consulta el tipo de conexión antes de reproducir y pausa si el dispositivo deja de indicar Wi-Fi.

## Límites actuales

Esto es un **prototipo fuente**, no un APK probado. Flutter no está instalado en el entorno en que se preparó; no se han podido ejecutar `flutter pub get`, análisis ni pruebas en Android.

La detección de Wi-Fi no mide el consumo real ni garantiza acceso a internet; algunas conexiones pueden cambiar de ruta antes de que llegue el evento. La selección de audio/video se basa inicialmente en la extensión y el códec se comprueba cuando se abre. La importación ocupa espacio adicional porque hace una copia privada. Faltan lectura de música ya guardada sin copiarla, letras, subtítulos, listas, asistente de voz, descargas autorizadas, catálogo con licencia, controles de bloqueo y reproducción de audio en segundo plano. La reproducción de video depende del ciclo de vida de la pantalla.

El diseño se integra directamente con las acciones existentes; no incluye fotografías ni copia componentes gráficos de otras aplicaciones. El icono de la cabecera es provisional hasta definir el emblema final.
