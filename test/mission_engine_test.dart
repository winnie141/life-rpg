import 'package:flutter_test/flutter_test.dart';
import 'package:life_rpg/mission_engine.dart';

void main() {
  const engine = MissionEngine();

  test('prioritizes the weakest and most neglected subject', () {
    final subjects = [
      StudySubject(
        id: 'algebra',
        name: 'Álgebra',
        mastery: 80,
        lastPracticedAt: DateTime(2026, 11, 25),
      ),
      StudySubject(
        id: 'physics',
        name: 'Física',
        mastery: 20,
        lastPracticedAt: DateTime(2026, 10, 1),
      ),
    ];

    final missions = engine.generateDaily(
      subjects: subjects,
      date: DateTime(2026, 11, 26),
      availableMinutes: 60,
    );

    expect(missions, hasLength(2));
    expect(missions.first.subjectId, 'physics');
    expect(missions.first.isMainQuest, isTrue);
    expect(missions.last.isMainQuest, isFalse);
  });

  test('does not generate missions without a configured subject', () {
    expect(
      engine.generateDaily(
        subjects: const [],
        date: DateTime(2026, 11, 26),
        availableMinutes: 60,
      ),
      isEmpty,
    );
  });

  test('respects a short available time budget', () {
    final missions = engine.generateDaily(
      subjects: const [StudySubject(id: 'math', name: 'Matemática')],
      date: DateTime(2026, 11, 26),
      availableMinutes: 15,
    );

    expect(missions, hasLength(1));
    expect(missions.single.estimatedMinutes, 15);
  });
}
