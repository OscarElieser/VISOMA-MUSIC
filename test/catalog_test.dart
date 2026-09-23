import 'package:flutter_test/flutter_test.dart';
import 'package:visoma_music/catalog.dart';

void main() {
  test('acepta un catálogo declarado y rechaza una URL insegura', () {
    final tracks = parseCatalog('{"version":1,"tracks":[{"title":"Pista propia",'
      '"url":"https://example.org/music.mp3","type":"audio","rights":"Autorización del creador"}]}');
    expect(tracks.single.title, 'Pista propia');
    expect(() => parseCatalog('{"version":1,"tracks":[{"title":"X",'
      '"url":"http://example.org/x.mp3","type":"audio","rights":"Sí"}]}'),
      throwsFormatException);
  });
}
