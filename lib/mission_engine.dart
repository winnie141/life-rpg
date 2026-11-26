class StudySubject {
  final String id;
  final String name;
  final String currentTopic;
  final int mastery; // 0..100, estimated from the player's own check-ins.
  final DateTime? lastPracticedAt;

  const StudySubject({
    required this.id,
    required this.name,
    this.currentTopic = '',
    this.mastery = 35,
    this.lastPracticedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currentTopic': currentTopic,
        'mastery': mastery,
        'lastPracticedAt': lastPracticedAt?.toIso8601String(),
      };

  factory StudySubject.fromJson(Map<String, dynamic> json) => StudySubject(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Materia',
        currentTopic: json['currentTopic'] as String? ?? '',
        mastery: (json['mastery'] as num?)?.toInt().clamp(0, 100).toInt() ?? 35,
        lastPracticedAt: json['lastPracticedAt'] == null
            ? null
            : DateTime.tryParse(json['lastPracticedAt'] as String),
      );
}

enum MissionEvidence { independent, withHints, withExample }

int evidenceAdjustedGain(int baseGain, MissionEvidence evidence) {
  final multiplier = switch (evidence) {
    MissionEvidence.independent => 1.0,
    MissionEvidence.withHints => 0.65,
    MissionEvidence.withExample => 0.35,
  };
  return (baseGain * multiplier).round();
}

class StudyMaterial {
  final String title;
  final String subject;
  final String topic;
  final String text;

  const StudyMaterial({
    required this.title,
    required this.subject,
    required this.topic,
    required this.text,
  });
}

class GeneratedMission {
  final String title;
  final String description;
  final String subjectId;
  final String? sourceTitle;
  final String? sourceExcerpt;
  final int estimatedMinutes;
  final bool isMainQuest;
  final int masteryGain;

  const GeneratedMission({
    required this.title,
    required this.description,
    required this.subjectId,
    this.sourceTitle,
    this.sourceExcerpt,
    required this.estimatedMinutes,
    required this.isMainQuest,
    required this.masteryGain,
  });
}

/// A deterministic planner: the same profile and date always produce the
/// same missions. It prioritizes weak and neglected subjects, not random tasks.
class MissionEngine {
  const MissionEngine();

  List<GeneratedMission> generateDaily({
    required List<StudySubject> subjects,
    required DateTime date,
    required int availableMinutes,
    List<StudyMaterial> materials = const [],
  }) {
    if (subjects.isEmpty || availableMinutes < 10) return const [];

    final ranked = [...subjects]..sort((a, b) {
        final scoreA = _priority(a, date);
        final scoreB = _priority(b, date);
        final byPriority = scoreB.compareTo(scoreA);
        return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
      });

    final chosen = ranked.first;
    final topic = chosen.currentTopic.trim().isEmpty
        ? 'los conceptos fundamentales'
        : chosen.currentTopic.trim();
    final chosenMaterial = _findMaterial(chosen, materials);
    final daySeed = date.year * 1000 + date.month * 50 + date.day;
    final phase = daySeed % 5;

    final sourceIntro = chosenMaterial == null
        ? ''
        : 'Usá como fuente "${chosenMaterial.title}" (Biblioteca). ';
    final main = switch (phase) {
      0 => GeneratedMission(
          title: 'Recuperación activa: ${chosen.name}',
          description: chosenMaterial == null
              ? 'Sin mirar apuntes, escribí lo que recordás sobre $topic. Después compará y corregí los huecos.'
              : '${sourceIntro}Leé el apartado sobre $topic, cerrá el material y reconstruí con tus palabras las ideas principales. Después compará y corregí lo que faltó.',
          subjectId: chosen.id,
          sourceTitle: chosenMaterial?.title,
          sourceExcerpt: _excerpt(chosenMaterial?.text),
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 3,
        ),
      1 => GeneratedMission(
          title: 'Entender el mecanismo: ${chosen.name}',
          description: chosenMaterial == null
              ? 'Explicá $topic con tus palabras. Identificá qué lo provoca, qué cambia y cómo reconocerlo en un ejercicio.'
              : '${sourceIntro}Explicá $topic con tus palabras. Identificá las ideas, relaciones y mecanismos que aparecen en el texto; señalá qué parte de la fuente respalda cada explicación.',
          subjectId: chosen.id,
          sourceTitle: chosenMaterial?.title,
          sourceExcerpt: _excerpt(chosenMaterial?.text),
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 3,
        ),
      2 => GeneratedMission(
          title: 'Resolver con guía: ${chosen.name}',
          description: chosenMaterial == null
              ? 'Elegí un ejercicio de $topic. Resolvelo paso a paso y anotá por qué elegís cada procedimiento.'
              : '${sourceIntro}Buscá en el material un ejemplo, procedimiento o afirmación sobre $topic. Reconstruí el razonamiento paso a paso y anotá por qué se hace cada paso. Si no hay ejercicios, convertí una afirmación del texto en una pregunta y respondela usando la fuente.',
          subjectId: chosen.id,
          sourceTitle: chosenMaterial?.title,
          sourceExcerpt: _excerpt(chosenMaterial?.text),
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 4,
        ),
      3 => GeneratedMission(
          title: 'Desafío independiente: ${chosen.name}',
          description: chosenMaterial == null
              ? 'Resolvé un ejercicio de $topic sin mirar un ejemplo. Si te trabás, registrá exactamente dónde.'
              : '${sourceIntro}Sin releer, formulá una pregunta importante sobre $topic y respondela de memoria. Después contrastá la respuesta con la fuente y anotá cualquier diferencia.',
          subjectId: chosen.id,
          sourceTitle: chosenMaterial?.title,
          sourceExcerpt: _excerpt(chosenMaterial?.text),
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 5,
        ),
      _ => GeneratedMission(
          title: 'Detectar y corregir errores: ${chosen.name}',
          description: chosenMaterial == null
              ? 'Revisá un ejercicio de $topic. Buscá el primer paso dudoso, corregilo y explicá qué regla faltó.'
              : '${sourceIntro}Escribí una explicación breve de $topic y comparala con el material. Detectá una omisión, contradicción o paso que no puedas justificar; corregilo citando la parte relevante de la fuente.',
          subjectId: chosen.id,
          sourceTitle: chosenMaterial?.title,
          sourceExcerpt: _excerpt(chosenMaterial?.text),
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 4,
        ),
    };

    final missions = <GeneratedMission>[main];
    if (availableMinutes >= 40 && ranked.length > 1) {
      final second = ranked[1];
      final secondMaterial = _findMaterial(second, materials);
      missions.add(GeneratedMission(
        title: 'Repaso breve: ${second.name}',
        description: secondMaterial == null
            ? 'Hacé 5 preguntas o un ejercicio corto sobre ${second.currentTopic.trim().isEmpty ? 'el último tema visto' : second.currentTopic.trim()}. Corregí sin mirar la solución primero.'
            : 'Usá "${secondMaterial.title}" de la Biblioteca. Formulá 3 preguntas sobre ${second.currentTopic.trim().isEmpty ? 'el tema' : second.currentTopic.trim()}, respondelas sin mirar y después verificá cada respuesta con la fuente.',
        subjectId: second.id,
        sourceTitle: secondMaterial?.title,
        sourceExcerpt: _excerpt(secondMaterial?.text),
        estimatedMinutes: 10,
        isMainQuest: false,
        masteryGain: 2,
      ));
    } else if (availableMinutes >= 40) {
      missions.add(GeneratedMission(
        title: 'Cierre Feynman',
        description:
            'Explicá en voz alta lo aprendido hoy como si se lo enseñaras a alguien que recién empieza. Detectá una duda real.',
        subjectId: chosen.id,
        estimatedMinutes: 10,
        isMainQuest: false,
        masteryGain: 2,
      ));
    }
    return missions;
  }

  StudyMaterial? _findMaterial(
    StudySubject subject,
    List<StudyMaterial> materials,
  ) {
    final matching = materials.where((material) {
      if (material.text.trim().isEmpty ||
          material.subject.trim().toLowerCase() != subject.name.trim().toLowerCase()) {
        return false;
      }
      final wantedTopic = subject.currentTopic.trim().toLowerCase();
      final materialTopic = material.topic.trim().toLowerCase();
      if (wantedTopic.isEmpty || materialTopic.isEmpty) return true;
      return wantedTopic.contains(materialTopic) || materialTopic.contains(wantedTopic);
    }).toList();
    if (matching.isEmpty) return null;
    matching.sort((a, b) => b.text.length.compareTo(a.text.length));
    return matching.first;
  }

  String? _excerpt(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.length <= 1200 ? cleaned : '${cleaned.substring(0, 1200)}…';
  }

  int _mainMinutes(int available) => available >= 30 ? 25 : available;

  double _priority(StudySubject subject, DateTime date) {
    final weakness = (100 - subject.mastery) / 100;
    final days = subject.lastPracticedAt == null
        ? 14
        : date.difference(subject.lastPracticedAt!).inDays.clamp(0, 30);
    final neglect = days / 30;
    return weakness * 0.65 + neglect * 0.35;
  }
}
