/// Offline helpers that turn extracted source text into readable study sections.
/// These helpers never invent academic content: they only split and select text
/// that actually exists in the user's uploaded material.
class StudyTextSection {
  final String text;
  final int index;
  const StudyTextSection(this.text, this.index);
}

class TopicLearningContent {
  const TopicLearningContent();

  List<StudyTextSection> sections(String source, {int maxLength = 1100}) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return const [];
    final paragraphs = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((part) => part.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final input = paragraphs.isNotEmpty
        ? paragraphs
        : normalized.split('\n').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    final result = <StudyTextSection>[];
    for (final paragraph in input) {
      if (paragraph.length <= maxLength) {
        result.add(StudyTextSection(paragraph, result.length + 1));
        continue;
      }
      var start = 0;
      while (start < paragraph.length) {
        var end = (start + maxLength).clamp(0, paragraph.length);
        if (end < paragraph.length) {
          final boundary = paragraph.lastIndexOf(' ', end);
          if (boundary > start + (maxLength ~/ 2)) end = boundary;
        }
        result.add(StudyTextSection(paragraph.substring(start, end).trim(), result.length + 1));
        start = end;
        while (start < paragraph.length && paragraph[start] == ' ') {
          start++;
        }
      }
    }
    return result;
  }

  /// Returns only passages that look like actual exercise statements.
  /// The heuristic is intentionally conservative; no synthetic exercise is
  /// presented as if it came from the uploaded guide.
  List<String> practiceExcerpts(String source, {int limit = 12}) {
    final candidates = sections(source, maxLength: 700).map((item) => item.text);
    final pattern = RegExp(
      r'(ejercicio|problema|resuelva|resolver|calcule|calcular|halle|determinar|demuestre|'
      r'justifique|encuentre|obtenga|grafique|considere|a partir de|dado que|'
      r'^\s*\d+(?:\.\d+)*[.)])',
      caseSensitive: false,
      multiLine: true,
    );
    final seen = <String>{};
    final result = <String>[];
    for (final candidate in candidates) {
      if (pattern.hasMatch(candidate) && seen.add(candidate.toLowerCase())) {
        result.add(candidate);
        if (result.length >= limit) break;
      }
    }
    return result;
  }
}
