/// Core data structures for the subject -> topic -> mastery system.
///
/// This file deliberately contains no UI or file-system code so the learning
/// model can be tested independently from the Flutter screens.
class SubjectSection {
  final String id;
  final String title;
  final String description;
  final String iconKey;

  const SubjectSection({
    required this.id,
    required this.title,
    required this.description,
    required this.iconKey,
  });

  static const List<SubjectSection> defaults = [
    SubjectSection(
      id: 'physics',
      title: 'Física',
      description: 'Movimiento, fuerzas, energía y fenómenos físicos.',
      iconKey: 'physics',
    ),
    SubjectSection(
      id: 'analysis',
      title: 'Análisis Matemático',
      description: 'Funciones, límites, derivadas, integrales y series.',
      iconKey: 'analysis',
    ),
    SubjectSection(
      id: 'algebra',
      title: 'Álgebra',
      description: 'Vectores, matrices, transformaciones y estructuras.',
      iconKey: 'algebra',
    ),
    SubjectSection(
      id: 'chemistry',
      title: 'Química',
      description: 'Materia, enlaces, reacciones y sistemas químicos.',
      iconKey: 'chemistry',
    ),
  ];
}

enum MasteryStage {
  recognition,
  understanding,
  application,
  integration,
}

extension MasteryStageDetails on MasteryStage {
  String get title {
    switch (this) {
      case MasteryStage.recognition:
        return 'Reconocimiento';
      case MasteryStage.understanding:
        return 'Comprensión';
      case MasteryStage.application:
        return 'Aplicación';
      case MasteryStage.integration:
        return 'Integración';
    }
  }

  String get description {
    switch (this) {
      case MasteryStage.recognition:
        return 'Identificar conceptos, símbolos, magnitudes y definiciones.';
      case MasteryStage.understanding:
        return 'Explicar con tus palabras qué significa y por qué sucede.';
      case MasteryStage.application:
        return 'Usar los conceptos para resolver ejercicios y situaciones.';
      case MasteryStage.integration:
        return 'Relacionar ideas y resolver problemas nuevos sin una receta.';
    }
  }
}

/// A topic keeps its own progress. achievedStage is the highest stage
/// demonstrated by the learner: 0 means not yet demonstrated, 1..4 map to
/// [MasteryStage] in order.
class StudyTopic {
  final String id;
  String title;
  int achievedStage;
  List<String> sourceDocumentIds;

  StudyTopic({
    required this.id,
    required this.title,
    int achievedStage = 0,
    List<String> sourceDocumentIds = const [],
  })  : achievedStage = achievedStage.clamp(0, 4).toInt(),
        sourceDocumentIds = List<String>.from(sourceDocumentIds);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'achievedStage': achievedStage,
        'sourceDocumentIds': sourceDocumentIds,
      };

  factory StudyTopic.fromJson(Map<String, dynamic> json) => StudyTopic(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Tema sin título',
        achievedStage: (json['achievedStage'] as num?)?.toInt() ?? 0,
        sourceDocumentIds:
            (json['sourceDocumentIds'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
      );

  String get currentStageLabel =>
      achievedStage == 0 ? 'Sin evaluar' : MasteryStage.values[achievedStage - 1].title;
}

class TopicSuggestion {
  final String title;
  final int sourceLine;

  const TopicSuggestion({
    required this.title,
    required this.sourceLine,
  });
}

/// Conservative, offline heading detector.
///
/// It only proposes headings that have recognizable structure (numbered
/// sections, explicit "Unidad/Tema/Capítulo" labels, or short uppercase
/// heading lines). It does not pretend to semantically understand arbitrary
/// paragraphs. When no reliable headings are found, the caller should ask the
/// user to add or split topics manually.
class TopicExtractor {
  const TopicExtractor();

  List<TopicSuggestion> extract(String sourceText) {
    if (sourceText.trim().isEmpty) return const [];

    final lines = sourceText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final suggestions = <TopicSuggestion>[];
    final seen = <String>{};

    for (var index = 0; index < lines.length; index++) {
      final raw = lines[index].trim();
      if (raw.isEmpty) continue;

      final candidate = _cleanHeading(raw);
      if (candidate == null || !_looksLikeHeading(raw, candidate)) continue;

      final key = _normalize(candidate);
      if (key.isEmpty || !_isUsefulHeading(candidate) || !seen.add(key)) {
        continue;
      }

      suggestions.add(TopicSuggestion(
        title: candidate,
        sourceLine: index + 1,
      ));
    }

    return suggestions;
  }

  String? _cleanHeading(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(
      RegExp(
        r'^(?:(?:cap[ií]tulo|unidad|tema|secci[oó]n|parte)\s*(?:n[º°.]?\s*)?[\dIVX.-]*\s*[:.)-]?\s*)',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceFirst(RegExp(r'^\d+(?:\.\d+)*[.)]?\s+'), '');
    value = value.replaceFirst(RegExp(r'^[•*–—-]\s*'), '');
    value = value.replaceFirst(RegExp(r'\s*[:：]$'), '');
    value = value.trim();
    return value.isEmpty ? null : value;
  }

  bool _looksLikeHeading(String raw, String candidate) {
    final explicitLabel = RegExp(
      r'^(cap[ií]tulo|unidad|tema|secci[oó]n|parte)\b',
      caseSensitive: false,
    ).hasMatch(raw);
    final numbered = RegExp(r'^\d+(?:\.\d+)*[.)]?\s+').hasMatch(raw);
    final letters = candidate.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
    final uppercase = letters.isNotEmpty && letters == letters.toUpperCase();
    final shortLine = candidate.length <= 72 && candidate.split(RegExp(r'\s+')).length <= 9;
    final sentenceLike = RegExp(r'[.!?]$').hasMatch(candidate);

    if (sentenceLike || candidate.length > 100) return false;
    if (explicitLabel || numbered) return shortLine;
    return uppercase && shortLine && letters.length >= 4;
  }

  bool _isUsefulHeading(String value) {
    final normalized = _normalize(value);
    const generic = {
      'introduccion',
      'introducción',
      'indice',
      'índice',
      'bibliografia',
      'bibliografía',
      'referencias',
      'objetivos',
      'conclusion',
      'conclusión',
    };
    return value.length >= 3 && !generic.contains(normalized);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-záéíóúüñ0-9]+'), ' ')
      .trim();
}
