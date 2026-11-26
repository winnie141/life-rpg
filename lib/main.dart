import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _missionsKey = 'life_rpg_missions_v1';
  static const String _notesKey = 'life_rpg_notes_v1';

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

    setState(() {
      _missions = loadedMissions;
      _notes = loadedNotes;
      _loading = false;
    });
  }

  Future<void> _saveMissions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _missionsKey,
      jsonEncode(_missions.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey,
      jsonEncode(_notes.map((n) => n.toJson()).toList()),
    );
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

    showDialog<void>(
      context: context,
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
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sin misiones registradas para este día. Tocá + para crear una.',
              ),
            ),
          ),
        ...dayMissions.map(
          (m) => Card(
            child: ListTile(
              leading: Checkbox(
                value: m.completed,
                onChanged: (val) {
                  setState(() => m.completed = val ?? false);
                  _saveMissions();
                },
              ),
              title: Text(
                '${m.isMainQuest ? "[Principal] " : ""}${m.title}',
                style: TextStyle(
                  decoration:
                      m.completed ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                '${m.area.label} · Prioridad ${m.priority.label}${m.estimatedMinutes != null ? " · ${m.estimatedMinutes} min" : ""}',
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

  Widget _buildMapView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Mapa de capacidades',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        ...LifeArea.values.map((area) {
          final count = _missions
              .where((m) => m.area == area && m.completed)
              .length;
          return Card(
            child: ListTile(
              title: Text(area.label),
              subtitle: const Text('Red de capacidades del área'),
              trailing: Text('$count completadas'),
            ),
          );
        }),
      ],
    );
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
        const Card(
          child: ListTile(
            title:  Text('Modo sin conexión'),
            subtitle:  Text('Datos guardados localmente en el dispositivo.'),
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
      title: 'LIFE RPG',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('LIFE RPG')),
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
