import 'package:flutter_test/flutter_test.dart';
import 'package:life_rpg/topic_learning_content.dart';

void main() {
  const content = TopicLearningContent();

  group('TopicLearningContent', () {
    test('splits uploaded text into readable sections without losing content', () {
      const source = 'Primer párrafo del apunte.\n\nSegundo párrafo con otra idea.';
      final sections = content.sections(source);
      expect(sections.map((item) => item.text).toList(), [
        'Primer párrafo del apunte.',
        'Segundo párrafo con otra idea.',
      ]);
    });

    test('splits long paragraphs into bounded chunks', () {
      final source = List.filled(80, 'palabra').join(' ');
      final sections = content.sections(source, maxLength: 100);
      expect(sections.length, greaterThan(1));
      expect(sections.every((item) => item.text.length <= 100), isTrue);
      expect(sections.map((item) => item.index).toList(),
          List.generate(sections.length, (index) => index + 1));
    });

    test('finds exercise excerpts only when exercise wording exists', () {
      const source = '''
Teoría: la fuerza neta produce aceleración.

Ejercicio 1. Calcule la aceleración de un cuerpo de masa 2 kg.

Considere un sistema sin rozamiento y determine la fuerza.
''';
      final excerpts = content.practiceExcerpts(source);
      expect(excerpts, hasLength(2));
      expect(excerpts.first, contains('Ejercicio 1'));
    });

    test('does not invent exercises when none are present', () {
      expect(content.practiceExcerpts('La derivada mide la tasa de variación.'), isEmpty);
      expect(content.sections('   '), isEmpty);
    });
  });
}
