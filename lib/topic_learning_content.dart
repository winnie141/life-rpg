/// Offline helpers that turn extracted source text into readable study sections.
/// These helpers never invent academic content: they only split and select text
/// that actually exists in the user's uploaded material.
class StudyTextSection {
  final String text;
  final int index;
  const StudyTextSection(this.text, this.index);
}

class StudyLessonBlock {
  final StudyTextSection section;
  final String label;
  final String checkQuestion;

  const StudyLessonBlock({
    required this.section,
    required this.label,
    required this.checkQuestion,
  });
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
        var end = (start + maxLength).clamp(0, paragraph.length).toInt();
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


  /// Organizes real source fragments into a guided reading path.
  /// Labels and questions are prompts; the academic content remains verbatim.
  List<StudyLessonBlock> lessonBlocks(String source, {int maxLength = 1100}) {
    return sections(source, maxLength: maxLength).map((section) {
      final text = section.text.toLowerCase();
      if (RegExp(r'\b(definici[oó]n|se define|se denomina|se llama|significa)\b').hasMatch(text)) {
        return StudyLessonBlock(
          section: section,
          label: 'Concepto / definición',
          checkQuestion: '¿Qué idea se está definiendo y qué características la distinguen?',
        );
      }
      if (RegExp(r'\b(ejemplo|resuelto|aplicaci[oó]n)\b').hasMatch(text)) {
        return StudyLessonBlock(
          section: section,
          label: 'Ejemplo / aplicación',
          checkQuestion: '¿Qué pasos se siguen y por qué cada uno tiene sentido?',
        );
      }
      if (RegExp(r'\b(teorema|propiedad|ley|corolario)\b').hasMatch(text)) {
        return StudyLessonBlock(
          section: section,
          label: 'Propiedad / resultado',
          checkQuestion: '¿Qué condiciones deben cumplirse y qué conclusión permite obtener?',
        );
      }
      if (RegExp(r'[=≈≤≥∫∑√∞]|\b(f[oó]rmula|ecuaci[oó]n|expresi[oó]n)\b').hasMatch(text)) {
        return StudyLessonBlock(
          section: section,
          label: 'Expresión matemática',
          checkQuestion: '¿Qué representa cada símbolo y en qué situación podés usar esta expresión?',
        );
      }
      if (RegExp(r'\b(paso|procedimiento|m[eé]todo|algoritmo)\b').hasMatch(text)) {
        return StudyLessonBlock(
          section: section,
          label: 'Procedimiento',
          checkQuestion: '¿Cuál es el orden de los pasos y qué justifica pasar de uno al siguiente?',
        );
      }
      return StudyLessonBlock(
        section: section,
        label: 'Desarrollo del material',
        checkQuestion: '¿Cuál es la idea principal de este fragmento y con qué parte del tema se conecta?',
      );
    }).toList();
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
