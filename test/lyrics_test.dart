import 'package:flutter_test/flutter_test.dart';
import 'package:visoma_music/lyrics.dart';

void main() {
  test('expande marcas repetidas y ordena líneas sincronizadas', () {
    final lines = parseLrc('[ar:Autor]\n[00:03.5][00:09.25]Estribillo\n[00:01.00]Inicio');
    expect(lines.map((line) => line.text), ['Inicio', 'Estribillo', 'Estribillo']);
    expect(lines.map((line) => line.at.inMilliseconds), [1000, 3500, 9250]);
    expect(activeLyricIndex(lines, const Duration(milliseconds: 9250)), 2);
    expect(activeLyricIndex(lines, Duration.zero), -1);
  });
}
