# Catálogo online VÍSOMA MUSIC

Hospeda un JSON UTF-8 accesible mediante HTTPS. Cada archivo multimedia debe ser una URL HTTPS **directa** y su propietario debe autorizar reproducción y, si se ofrece el botón offline, descarga. El campo `rights` es una declaración del operador; la app no verifica contratos.

```json
{
  "version": 1,
  "tracks": [
    {
      "title": "Nombre de una canción autorizada",
      "artist": "Nombre del artista",
      "album": "Álbum o colección",
      "genre": "Género musical",
      "url": "https://tu-dominio.example/media/cancion.mp3",
      "type": "audio",
      "rights": "Permiso del artista para reproducir y descargar",
      "downloadAllowed": true
    }
  ]
}
```

El máximo actual es 500 entradas y 1 MB por manifiesto. La app añade las pistas a la biblioteca personal. Si `downloadAllowed` falta o es `false`, la pista se reproduce online sin botón de descarga. Las descargas offline individuales requieren Wi-Fi y no pueden superar 250 MB. Cambiar el JSON remoto no sincroniza automáticamente los elementos ya importados.
