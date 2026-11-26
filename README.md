# LIFE RPG — Android starter 0.1

Este es el primer proyecto Flutter de LIFE RPG. Incluye una app Android con estética minimalista, navegación local y persistencia de las misiones marcadas como completadas.

## Estado real de esta entrega
- Pantallas: Hoy, Mapa, Biblioteca y Perfil.
- Misiones iniciales de demostración.
- Progreso diario.
- Persistencia local de las misiones mediante `shared_preferences`.
- Sin cuenta, servidor ni conexión a Internet en tiempo de uso.
- Todavía NO incluye un modelo de IA local, importación real de PDF, motor adaptativo ni APK compilado.

## Requisitos para compilar
- Flutter SDK estable.
- Android Studio con Android SDK.
- Un dispositivo Android o emulador.

## Compilar
Desde la carpeta `life_rpg`:

```bash
flutter pub get
flutter doctor
flutter run
```

Para generar el APK:

```bash
flutter build apk --release
```

El APK se genera en:
`build/app/outputs/flutter-apk/app-release.apk`

## Próximas etapas
1. Reemplazar misiones de demostración por un motor de decisiones persistente.
2. Añadir objetivos y dimensiones de progreso (comprensión, procedimiento, independencia, transferencia y retención).
3. Añadir almacenamiento estructurado para materias, temas, habilidades y evidencias.
4. Importar documentos y construir una biblioteca local.
5. Evaluar integración de un modelo LLM local compatible con el hardware Android objetivo. La disponibilidad y velocidad dependerán del dispositivo y del tamaño/cuanti­zación del modelo.
