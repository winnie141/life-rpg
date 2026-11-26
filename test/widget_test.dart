import 'package:flutter_test/flutter_test.dart';
import 'package:life_rpg/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('LIFE RPG arranca y muestra las secciones principales',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LifeRpgApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('LIFE RPG'), findsOneWidget);
    expect(find.text('Materias'), findsNWidgets(2));
    expect(find.text('Física'), findsOneWidget);
    expect(find.text('Análisis Matemático'), findsOneWidget);
    expect(find.text('Álgebra'), findsOneWidget);
    expect(find.text('Química'), findsOneWidget);
    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });
}
