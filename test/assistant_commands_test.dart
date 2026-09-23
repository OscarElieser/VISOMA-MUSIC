import 'package:flutter_test/flutter_test.dart';
import 'package:visoma_music/assistant_commands.dart';

void main() {
  test('interpreta acciones locales sin confundir una canción con modo offline', () {
    expect(parseAssistantCommand('pon mi canción').action, AssistantAction.play);
    expect(parseAssistantCommand('pon mi canción').query, 'mi canción');
    expect(parseAssistantCommand('modo viaje').action, AssistantAction.travel);
    expect(parseAssistantCommand('pausar').action, AssistantAction.pause);
  });
}
