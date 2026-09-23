/// A timestamped line from an LRC lyric file.
class LyricLine {
  const LyricLine(this.at, this.text);

  final Duration at;
  final String text;
}

/// Parses common LRC timestamps such as [01:23.45]. Metadata is ignored.
/// A line with multiple timestamps is expanded into multiple entries.
List<LyricLine> parseLrc(String content) {
  final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]');
  final lines = <LyricLine>[];
  for (final raw in content.split(RegExp(r'\r?\n'))) {
    final matches = stamp.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final words = raw.replaceAll(stamp, '').trim();
    if (words.isEmpty) continue;
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      if (seconds > 59) continue;
      final fraction = match.group(3) ?? '0';
      final milliseconds = int.parse(fraction.padRight(3, '0'));
      lines.add(LyricLine(Duration(minutes: minutes, seconds: seconds,
          milliseconds: milliseconds), words));
    }
  }
  lines.sort((a, b) => a.at.compareTo(b.at));
  return lines;
}

int activeLyricIndex(List<LyricLine> lines, Duration position) {
  for (var index = lines.length - 1; index >= 0; index--) {
    if (position >= lines[index].at) return index;
  }
  return -1;
}
