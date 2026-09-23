enum AssistantAction { play, pause, next, previous, travel, offline, online, help, unknown }

class AssistantCommand {
  const AssistantCommand(this.action, [this.query = '']);
  final AssistantAction action;
  final String query;
}

/// On-device command parser. It handles library actions; it is not a language model.
AssistantCommand parseAssistantCommand(String input) {
  final text = input.trim().toLowerCase();
  if (text.isEmpty || text == 'ayuda') return const AssistantCommand(AssistantAction.help);
  if (text.contains('modo viaje')) return const AssistantCommand(AssistantAction.travel);
  if (text.contains('sin conexión') || text.contains('sin conexion')) {
    return const AssistantCommand(AssistantAction.offline);
  }
  if (text.contains('modo online') || text.contains('modo en línea')) {
    return const AssistantCommand(AssistantAction.online);
  }
  if (text.contains('siguiente')) return const AssistantCommand(AssistantAction.next);
  if (text.contains('anterior')) return const AssistantCommand(AssistantAction.previous);
  if (text == 'pausa' || text.contains('pausar')) return const AssistantCommand(AssistantAction.pause);
  final play = RegExp(r'(?:reproduce|pon|escucha)\s+(.+)').firstMatch(text);
  if (play != null) return AssistantCommand(AssistantAction.play, play.group(1)!.trim());
  return const AssistantCommand(AssistantAction.unknown);
}
