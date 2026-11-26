import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mission_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LifeRpgApp());
}

enum LifeArea {
  knowledge('Conocimiento'),
  bodyEnergy('Cuerpo y energía'),
  selfDirection('Autodirección'),
  practicalLife('Vida práctica');

  final String label;
  const LifeArea(this.label);
}

enum MissionPriority {
  low('Baja'),
  medium('Media'),
  high('Alta');

  final String label;
  const MissionPriority(this.label);
}

class MissionItem {
  final String id;
  String title;
  String description;
  LifeArea area;
  MissionPriority priority;
  bool isMainQuest;
  bool completed;
  int? estimatedMinutes;
  String dayKey;
  String? subjectId;
  int masteryGain;
  bool progressRecorded;
  String? completionEvidence;

  MissionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.area,
    required this.priority,
    required this.isMainQuest,
    required this.completed,
    this.estimatedMinutes,
    required this.dayKey,
    this.subjectId,
    this.masteryGain = 0,
    this.progressRecorded = false,
    this.completionEvidence,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'area': area.name,
        'priority': priority.name,
        'isMainQuest': isMainQuest,
        'completed': completed,
        'estimatedMinutes': estimatedMinutes,
        'dayKey': dayKey,
        'subjectId': subjectId,
        'masteryGain': masteryGain,
        'progressRecorded': progressRecorded,
        'completionEvidence': completionEvidence,
      };

  factory MissionItem.fromJson(Map<String, dynamic> json) => MissionItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        area: LifeArea.values.firstWhere(
          (e) => e.name == json['area'],
          orElse: () => LifeArea.knowledge,
        ),
        priority: MissionPriority.values.firstWhere(
          (e) => e.name == json['priority'],
          orElse: () => MissionPriority.medium,
        ),
        isMainQuest: json['isMainQuest'] as bool? ?? false,
        completed: json['completed'] as bool? ?? false,
        estimatedMinutes: json['estimatedMinutes'] as int?,
        dayKey: json['dayKey'] as String? ?? dateToKey(DateTime.now()),
        subjectId: json['subjectId'] as String?,
        masteryGain: json['masteryGain'] as int? ?? 0,
        progressRecorded: json['progressRecorded'] as bool? ?? false,
        completionEvidence: json['completionEvidence'] as String?,
      );
}

class LibraryNoteItem {
  final String id;
  String subject;
  String topic;
  String title;
  String content;

  LibraryNoteItem({
    required this.id,
    required this.subject,
    required this.topic,
    required this.title,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'topic': topic,
        'title': title,
        'content': content,
      };

  factory LibraryNoteItem.fromJson(Map<String, dynamic> json) => LibraryNoteItem(
        id: json['id'] as String,
        subject: json['subject'] as String? ?? 'General',
        topic: json['topic'] as String? ?? 'Tema',
        title: json['title'] as String? ?? 'Nota',
        content: json['content'] as String? ?? '',
      );
}

String dateToKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class LifeRpgApp extends StatefulWidget {
  const LifeRpgApp({super.key});

  @override
  State<LifeRpgApp> createState() => _LifeRpgAppState();
}

class _LifeRpgAppState extends State<LifeRpgApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static const String _missionsKey = 'life_rpg_missions_v1';
  static const String _notesKey = 'life_rpg_notes_v1';
  static const String _subjectsKey = 'life_rpg_subjects_v1';
  static const String _dailyMinutesKey = 'life_rpg_daily_minutes_v1';
  final MissionEngine _missionEngine = const MissionEngine();
  List<StudySubject> _studySubjects = [];
  int _dailyMinutes = 45;

  int _selectedIndex = 0;
  DateTime _selectedDate = DateTime.now();
  List<MissionItem> _missions = [];
  List<LibraryNoteItem> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMissions = prefs.getString(_missionsKey);
    final rawNotes = prefs.getString(_notesKey);
    final rawSubjects = prefs.getString(_subjectsKey);
    final savedMinutes = prefs.getInt(_dailyMinutesKey) ?? 45;

    List<MissionItem> loadedMissions = [];
    if (rawMissions != null && rawMissions.isNotEmpty) {
      final decoded = jsonDecode(rawMissions) as List<dynamic>;
      loadedMissions = decoded
          .map((item) => MissionItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    List<LibraryNoteItem> loadedNotes = [];
    if (rawNotes != null && rawNotes.isNotEmpty) {
      final decoded = jsonDecode(rawNotes) as List<dynamic>;
      loadedNotes = decoded
          .map((item) => LibraryNoteItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    List<StudySubject> loadedSubjects = [];
    if (rawSubjects != null && rawSubjects.isNotEmpty) {
      final decoded = jsonDecode(rawSubjects) as List<dynamic>;
      loadedSubjects = decoded
          .map((item) => StudySubject.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    setState(() {
      _missions = loadedMissions;
      _notes = loadedNotes;
      _studySubjects = loadedSubjects;
      _dailyMinutes = savedMinutes;
      _loading = false;
    });
    await _ensureDailyMissions();
  }

  Future<void> _saveMissions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _missionsKey,
      jsonEncode(_missions.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _saveStudySubjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _subjectsKey,
      jsonEncode(_studySubjects.map((subject) => subject.toJson()).toList()),
    );
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey,
      jsonEncode(_notes.map((n) => n.toJson()).toList()),
    );
  }

  Future<void> _ensureDailyMissions() async {
    if (_studySubjects.isEmpty) return;
    final todayKey = dateToKey(DateTime.now());
    final alreadyGenerated = _missions.any(
      (m) => m.dayKey == todayKey && m.subjectId != null,
    );
    if (alreadyGenerated) return;

    final generated = _missionEngine.generateDaily(
      subjects: _studySubjects,
      date: DateTime.now(),
      availableMinutes: _dailyMinutes,
    );
    if (generated.isEmpty) return;

    setState(() {
      _missions.addAll(generated.map((draft) => MissionItem(
            id: DateTime.now().microsecondsSinceEpoch.toString() +
                draft.subjectId +
                draft.title.hashCode.toString(),
            title: draft.title,
            description: draft.description,
            area: LifeArea.knowledge,
            priority: draft.isMainQuest
                ? MissionPriority.high
                : MissionPriority.medium,
            isMainQuest: draft.isMainQuest,
            completed: false,
            estimatedMinutes: draft.estimatedMinutes,
            dayKey: todayKey,
            subjectId: draft.subjectId,
            masteryGain: draft.masteryGain,
          )));
    });
    await _saveMissions();
  }

  Future<void> _configureStudyRoute() async {
    final subjectsCtrl = TextEditingController(
      text: _studySubjects
          .map((s) => s.currentTopic.trim().isEmpty
              ? s.name
              : '${s.name} | ${s.currentTopic}')
          .join('\n'),
    );
    final minutesCtrl = TextEditingController(text: _dailyMinutes.toString());
    final dialogContext = _navigatorKey.currentState!.overlay!.context;
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar mi ruta'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'La app usa estos datos para elegir qué conviene practicar. '
                'Una materia por línea. Podés agregar el tema actual después de |.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectsCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Materias u objetivos de aprendizaje',
                  hintText: 'Física | Dinámica\nÁlgebra | Autovalores',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutos disponibles por día',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar ruta'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final parsed = subjectsCtrl.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) {
        final parts = line.split('|');
        final name = parts.first.trim();
        final topic = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
        final previous = _studySubjects.where(
          (subject) => subject.name.toLowerCase() == name.toLowerCase(),
        );
        final old = previous.isEmpty ? null : previous.first;
        return StudySubject(
          id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString() + name,
          name: name,
          currentTopic: topic,
          mastery: old?.mastery ?? 35,
          lastPracticedAt: old?.lastPracticedAt,
        );
      }).toList();
      final parsedMinutes = int.tryParse(minutesCtrl.text.trim()) ?? 45;
      setState(() {
        _studySubjects = parsed;
        _dailyMinutes = parsedMinutes.clamp(10, 240).toInt();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _subjectsKey,
        jsonEncode(_studySubjects.map((s) => s.toJson()).toList()),
      );
      await prefs.setInt(_dailyMinutesKey, _dailyMinutes);
      final todayKey = dateToKey(DateTime.now());
      setState(() {
        _missions.removeWhere(
          (mission) => mission.dayKey == todayKey && mission.subjectId != null,
        );
      });
      await _saveMissions();
      await _ensureDailyMissions();
    }
    subjectsCtrl.dispose();
    minutesCtrl.dispose();
  }


  Future<MissionEvidence?> _askMissionEvidence(MissionItem mission) {
    return showDialog<MissionEvidence>(
      context: _navigatorKey.currentState!.overlay!.context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cómo te fue?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Antes de registrar el avance de “${mission.title}”, contame '
                'cuánta ayuda necesitaste. Así el progreso refleja mejor lo que '
                'realmente dominás.',
              ),
              const SizedBox(height: 8),
              _evidenceAction(ctx, MissionEvidence.withExample,
                  'Necesité mirar un ejemplo',
                  'La terminé siguiendo un procedimiento.'),
              _evidenceAction(ctx, MissionEvidence.withHints,
                  'Con algunas pistas',
                  'Avancé, pero necesité ayuda en algunos pasos.'),
              _evidenceAction(ctx, MissionEvidence.independent,
                  'Por mi cuenta',
                  'La resolví o expliqué sin mirar la solución.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _evidenceAction(BuildContext dialogContext, MissionEvidence evidence,
      String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.pop(dialogContext, evidence),
    );
  }

  Future<void> _setMissionCompleted(MissionItem mission, bool completed) async {
    if (!completed) {
      setState(() => mission.completed = false);
      await _saveMissions();
      return;
    }
    if (mission.completed) return;

    MissionEvidence? evidence;
    if (mission.subjectId != null && !mission.progressRecorded) {
      evidence = await _askMissionEvidence(mission);
      if (evidence == null || !mounted) return;
    }

    setState(() {
      mission.completed = true;
      if (evidence != null && !mission.progressRecorded) {
        final index = _studySubjects.indexWhere(
          (subject) => subject.id == mission.subjectId,
        );
        if (index >= 0) {
          final subject = _studySubjects[index];
          final gain = evidenceAdjustedGain(mission.masteryGain, evidence);
          _studySubjects[index] = StudySubject(
            id: subject.id,
            name: subject.name,
            currentTopic: subject.currentTopic,
            mastery: (subject.mastery + gain).clamp(0, 100).toInt(),
            lastPracticedAt: DateTime.now(),
          );
          mission.completionEvidence = evidence.name;
          mission.progressRecorded = true;
        }
      }
    });
    await _saveMissions();
    await _saveStudySubjects();
  }

  void _addOrEditMission({MissionItem? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final minCtrl = TextEditingController(
      text: existing?.estimatedMinutes?.toString() ?? '',
    );
    LifeArea selectedArea = existing?.area ?? LifeArea.knowledge;
    MissionPriority selectedPriority = existing?.priority ?? MissionPriority.medium;
    bool isMain = existing?.isMainQuest ?? false;

    final dialogContext = _navigatorKey.currentState!.overlay!.context;
    showDialog<void>(
      context: dialogContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Nueva misión' : 'Editar misión'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Título'),
                    ),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Descripción'),
                    ),
                    TextField(
                      controller: minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duración estimada (min, opcional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<LifeArea>(
                      value: selectedArea,
                      decoration: const InputDecoration(labelText: 'Área'),
                      items: LifeArea.values
                          .map(
                            (a) => DropdownMenuItem(
                              value: a,
                              child: Text(a.label),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedArea = val);
                      },
                    ),
                    DropdownButtonFormField<MissionPriority>(
                      value: selectedPriority,
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                      items: MissionPriority.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.label),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedPriority = val);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Misión principal del día'),
                      value: isMain,
                      onChanged: (val) => setDialogState(() => isMain = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    final parsedMins = int.tryParse(minCtrl.text.trim());
                    setState(() {
                      if (existing == null) {
                        _missions.add(
                          MissionItem(
                            id: DateTime.now().microsecondsSinceEpoch.toString(),
                            title: title,
                            description: descCtrl.text.trim(),
                            area: selectedArea,
                            priority: selectedPriority,
                            isMainQuest: isMain,
                            completed: false,
                            estimatedMinutes: parsedMins,
                            dayKey: dateToKey(_selectedDate),
                          ),
                        );
                      } else {
                        existing.title = title;
                        existing.description = descCtrl.text.trim();
                        existing.area = selectedArea;
                        existing.priority = selectedPriority;
                        existing.isMainQuest = isMain;
                        existing.estimatedMinutes = parsedMins;
                      }
                    });
                    _saveMissions();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addNote() {
    final subjectCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva nota de estudio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(labelText: 'Materia'),
              ),
              TextField(
                controller: topicCtrl,
                decoration: const InputDecoration(labelText: 'Tema'),
              ),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              TextField(
                controller: contentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Resumen o apunte'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              setState(() {
                _notes.add(
                  LibraryNoteItem(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    subject: subjectCtrl.text.trim().isEmpty
                        ? 'General'
                        : subjectCtrl.text.trim(),
                    topic: topicCtrl.text.trim().isEmpty
                        ? 'Tema'
                        : topicCtrl.text.trim(),
                    title: titleCtrl.text.trim(),
                    content: contentCtrl.text.trim(),
                  ),
                );
              });
              _saveNotes();
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayView() {
    final key = dateToKey(_selectedDate);
    final dayMissions = _missions.where((m) => m.dayKey == key).toList();
    final completedCount = dayMissions.where((m) => m.completed).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Día: $key',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _selectedDate =
                        _selectedDate.subtract(const Duration(days: 1));
                  }),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                  }),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
        Text('Completadas hoy: $completedCount / ${dayMissions.length}'),
        const SizedBox(height: 12),
        if (dayMissions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Todavía no hay una ruta configurada. Configurá tus materias y la app va a generar misiones según tus prioridades.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _configureStudyRoute,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Configurar mi ruta'),
                  ),
                ],
              ),
            ),
          ),
        ...dayMissions.map(
          (m) => Card(
            child: ListTile(
              leading: Checkbox(
                value: m.completed,
                onChanged: (val) => _setMissionCompleted(m, val ?? false),
              ),
              title: Text(
                '${m.isMainQuest ? "[Principal] " : ""}${m.title}',
                style: TextStyle(
                  decoration:
                      m.completed ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                '${m.area.label} · Prioridad ${m.priority.label}'
                '${m.estimatedMinutes != null ? " · ${m.estimatedMinutes} min" : ""}'
                '${m.completionEvidence == null ? "" : " · ${_evidenceLabel(m.completionEvidence!)}"}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _addOrEditMission(existing: m),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() => _missions.removeWhere((x) => x.id == m.id));
                      _saveMissions();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _evidenceLabel(String value) {
    switch (value) {
      case 'independent':
        return 'Resuelta sin ayuda';
      case 'withHints':
        return 'Resuelta con pistas';
      case 'withExample':
        return 'Resuelta con ejemplo';
      default:
        return 'Evidencia registrada';
    }
  }

  Widget _buildMapView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Mapa de capacidades',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tu avance se construye con práctica registrada. El porcentaje es una estimación inicial, no una nota ni una certificación.',
        ),
        const SizedBox(height: 12),
        ...LifeArea.values.map((area) {
          final count = _missions
              .where((m) => m.area == area && m.completed)
              .length;
          return Card(
            child: ListTile(
              leading: Icon(_areaIcon(area)),
              title: Text(area.label),
              subtitle: Text(
                area == LifeArea.knowledge
                    ? '${_studySubjects.length} materias en tu ruta'
                    : 'Área preparada para futuras misiones',
              ),
              trailing: Text('$count'),
            ),
          );
        }),
        const SizedBox(height: 12),
        Text('Ruta de aprendizaje',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_studySubjects.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Todavía no hay materias'),
              subtitle: const Text('Configurá tu ruta para empezar a construir el mapa.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _configureStudyRoute,
            ),
          ),
        ..._studySubjects.map((subject) {
          final mastery = subject.mastery.clamp(0, 100);
          final recent = subject.lastPracticedAt == null
              ? 'Todavía sin práctica registrada'
              : 'Última práctica: ${dateToKey(subject.lastPracticedAt!)}';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(subject.name,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Text('$mastery%'),
                    ],
                  ),
                  if (subject.currentTopic.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subject.currentTopic,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: mastery / 100),
                  const SizedBox(height: 8),
                  Text(recent,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _configureStudyRoute,
          icon: const Icon(Icons.tune),
          label: const Text('Editar ruta de aprendizaje'),
        ),
      ],
    );
  }

  IconData _areaIcon(LifeArea area) {
    switch (area) {
      case LifeArea.knowledge:
        return Icons.psychology_alt_outlined;
      case LifeArea.bodyEnergy:
        return Icons.bolt_outlined;
      case LifeArea.selfDirection:
        return Icons.explore_outlined;
      case LifeArea.practicalLife:
        return Icons.handyman_outlined;
    }
  }

  Widget _buildLibraryView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Biblioteca', style: Theme.of(context).textTheme.titleLarge),
            FilledButton.icon(
              onPressed: _addNote,
              icon: const Icon(Icons.add),
              label: const Text('Nueva nota'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_notes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Todavía no cargaste apuntes o temas.'),
            ),
          ),
        ..._notes.map(
          (n) => Card(
            child: ListTile(
              title: Text(n.title),
              subtitle: Text('${n.subject} · ${n.topic}\n${n.content}'),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  setState(() => _notes.removeWhere((x) => x.id == n.id));
                  _saveNotes();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileView() {
    final totalCompleted = _missions.where((m) => m.completed).length;
    final activeDays =
        _missions.where((m) => m.completed).map((m) => m.dayKey).toSet().length;
    final averageMastery = _studySubjects.isEmpty
        ? 0
        : (_studySubjects.fold<int>(0, (sum, s) => sum + s.mastery) /
                _studySubjects.length)
            .round();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Perfil', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('Misiones completadas en total'),
            trailing: Text('$totalCompleted'),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Días activos registrados'),
            trailing: Text('$activeDays'),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Dominio estimado de tu ruta'),
            subtitle: Text(
              _studySubjects.isEmpty
                  ? 'Configurá materias para comenzar a medir tu progreso.'
                  : 'Promedio de ${_studySubjects.length} materias. Se actualiza al completar misiones.',
            ),
            trailing: Text('$averageMastery%'),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Modo sin conexión'),
            subtitle: const Text('Datos guardados localmente en el dispositivo.'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildTodayView(),
      _buildMapView(),
      _buildLibraryView(),
      _buildProfileView(),
    ];

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'LIFE RPG',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('LIFE RPG'),
          actions: [
            IconButton(
              tooltip: 'Configurar ruta',
              onPressed: _configureStudyRoute,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : screens[_selectedIndex],
        floatingActionButton: _selectedIndex == 0
            ? FloatingActionButton(
                onPressed: () => _addOrEditMission(),
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today), label: 'Hoy'),
            NavigationDestination(icon: Icon(Icons.hub), label: 'Mapa'),
            NavigationDestination(
              icon: Icon(Icons.library_books),
              label: 'Biblioteca',
            ),
            NavigationDestination(icon: Icon(Icons.person), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}
