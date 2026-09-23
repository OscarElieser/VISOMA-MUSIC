import 'dart:convert';

class CatalogTrack {
  const CatalogTrack({required this.title, required this.url,
    required this.video, required this.rights, required this.downloadAllowed,
    this.artist, this.album, this.genre});

  final String title;
  final String url;
  final bool video;
  final String rights;
  final bool downloadAllowed;
  final String? artist;
  final String? album;
  final String? genre;
}

/// Imports an operator-provided catalog. `rights` is a declaration from the
/// catalog operator, not an automated verification of music licensing.
List<CatalogTrack> parseCatalog(String jsonText) {
  final document = jsonDecode(jsonText);
  if (document is! Map<String, dynamic> || document['version'] != 1 ||
      document['tracks'] is! List) {
    throw const FormatException('Catálogo inválido: se esperaba versión 1 y tracks.');
  }
  final tracks = document['tracks'] as List;
  if (tracks.length > 500) throw const FormatException('Máximo 500 elementos por catálogo.');
  return tracks.map((raw) {
    if (raw is! Map<String, dynamic>) throw const FormatException('Entrada inválida.');
    final title = raw['title'];
    final url = raw['url'];
    final rights = raw['rights'];
    final type = raw['type'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (title is! String || title.trim().isEmpty ||
        uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        rights is! String || rights.trim().isEmpty ||
        (type != 'audio' && type != 'video')) {
      throw const FormatException('Faltan título, URL HTTPS, tipo o declaración de derechos.');
    }
    return CatalogTrack(title: title.trim(), url: uri.toString(),
      video: type == 'video', rights: rights.trim(),
      downloadAllowed: raw['downloadAllowed'] == true,
      artist: raw['artist'] is String ? raw['artist'] as String : null,
      album: raw['album'] is String ? raw['album'] as String : null,
      genre: raw['genre'] is String ? raw['genre'] as String : null);
  }).toList();
}
