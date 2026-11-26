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

class GeneratedMission {
  final String title;
  final String description;
  final String subjectId;
  final int estimatedMinutes;
  final bool isMainQuest;
  final int masteryGain;

  const GeneratedMission({
    required this.title,
    required this.description,
    required this.subjectId,
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
    final daySeed = date.year * 1000 + date.month * 50 + date.day;
    final phase = daySeed % 5;

    final main = switch (phase) {
      0 => GeneratedMission(
          title: 'Recuperación activa: ${chosen.name}',
          description:
              'Sin mirar apuntes, escribí lo que recordás sobre $topic. Después compará y corregí los huecos.',
          subjectId: chosen.id,
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 3,
        ),
      1 => GeneratedMission(
          title: 'Entender el mecanismo: ${chosen.name}',
          description:
              'Explicá $topic con tus palabras. Identificá qué lo provoca, qué cambia y cómo reconocerlo en un ejercicio.',
          subjectId: chosen.id,
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 3,
        ),
      2 => GeneratedMission(
          title: 'Resolver con guía: ${chosen.name}',
          description:
              'Elegí un ejercicio de $topic. Resolvelo paso a paso y anotá por qué elegís cada procedimiento.',
          subjectId: chosen.id,
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 4,
        ),
      3 => GeneratedMission(
          title: 'Desafío independiente: ${chosen.name}',
          description:
              'Resolvé un ejercicio de $topic sin mirar un ejemplo. Si te trabás, registrá exactamente dónde.',
          subjectId: chosen.id,
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 5,
        ),
      _ => GeneratedMission(
          title: 'Detectar y corregir errores: ${chosen.name}',
          description:
              'Revisá un ejercicio de $topic. Buscá el primer paso dudoso, corregilo y explicá qué regla faltó.',
          subjectId: chosen.id,
          estimatedMinutes: _mainMinutes(availableMinutes),
          isMainQuest: true,
          masteryGain: 4,
        ),
    };

    final missions = <GeneratedMission>[main];
    if (availableMinutes >= 40 && ranked.length > 1) {
      final second = ranked[1];
      missions.add(GeneratedMission(
        title: 'Repaso breve: ${second.name}',
        description:
            'Hacé 5 preguntas o un ejercicio corto sobre ${second.currentTopic.trim().isEmpty ? 'el último tema visto' : second.currentTopic.trim()}. Corregí sin mirar la solución primero.',
        subjectId: second.id,
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
