import 'package:flutter_test/flutter_test.dart';
import 'package:life_rpg/main.dart';

void main() {
  testWidgets('LIFE RPG arranca y muestra las secciones principales',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LifeRpgApp());
    await tester.pumpAndSettle();

    expect(find.text('LIFE RPG'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });
}
