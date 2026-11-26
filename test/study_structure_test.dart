import 'package:flutter_test/flutter_test.dart';
import 'package:life_rpg/study_structure.dart';

void main() {
  const extractor = TopicExtractor();

  group('TopicExtractor', () {
    test('detects numbered sections and removes numbering', () {
      final topics = extractor.extract('''
Unidad 1: CINEMÁTICA
Texto introductorio del tema.
2. Dinámica
Contenido de dinámica.
3.1. Leyes de Newton
Más contenido.
''');

      expect(topics.map((topic) => topic.title).toList(), [
        'CINEMÁTICA',
        'Dinámica',
        'Leyes de Newton',
      ]);
      expect(topics.map((topic) => topic.sourceLine).toList(), [1, 3, 5]);
    });

    test('detects short uppercase headings', () {
      final topics = extractor.extract('''
FÍSICA
Texto que explica el área.
TRABAJO Y ENERGÍA
Texto que desarrolla el tema.
''');

      expect(topics.map((topic) => topic.title).toList(), [
        'FÍSICA',
        'TRABAJO Y ENERGÍA',
      ]);
    });

    test('does not treat ordinary sentences as headings', () {
      final topics = extractor.extract('''
La segunda ley de Newton relaciona la fuerza con la aceleración.
Cuando aumenta la masa, cambia la aceleración para una fuerza dada.
Este texto explica el fenómeno con un ejemplo.
''');

      expect(topics, isEmpty);
    });

    test('does not return duplicate headings', () {
      final topics = extractor.extract('''
1. Cinemática
Contenido.
2. CINEMÁTICA
Otro contenido.
''');

      expect(topics, hasLength(1));
    });

    test('returns no suggestions for empty text', () {
      expect(extractor.extract('  \n  '), isEmpty);
    });
  });

  group('StudyTopic', () {
    test('clamps progress and survives JSON round trip', () {
      final topic = StudyTopic(
        id: 'topic-1',
        title: 'Dinámica',
        achievedStage: 8,
        sourceDocumentIds: ['doc-1'],
      );

      expect(topic.achievedStage, 4);
      final restored = StudyTopic.fromJson(topic.toJson());
      expect(restored.title, 'Dinámica');
      expect(restored.achievedStage, 4);
      expect(restored.sourceDocumentIds, ['doc-1']);
    });
  });

  test('has the four planned subject sections', () {
    expect(
      SubjectSection.defaults.map((section) => section.id).toList(),
      ['physics', 'analysis', 'algebra', 'chemistry'],
    );
    expect(MasteryStage.values, hasLength(4));
  });
}


  group('ProgramTopicParser', () {
    const parser = ProgramTopicParser();

    test('preserves syllabus order and removes numbering', () {
      expect(
        parser.parse('''
Unidad 1: Límites
1.1 Continuidad
2. Derivadas
• Aplicaciones de la derivada
'''),
        ['Límites', 'Continuidad', 'Derivadas', 'Aplicaciones de la derivada'],
      );
    });

    test('ignores blank and duplicate lines', () {
      expect(parser.parse('''
Integrales
     
Integrales
Integrales definidas
'''), ['Integrales', 'Integrales definidas']);
    });
  });
