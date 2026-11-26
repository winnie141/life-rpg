import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'study_structure.dart';

class SubjectLibraryScreen extends StatefulWidget {
  const SubjectLibraryScreen({super.key});

  @override
  State<SubjectLibraryScreen> createState() => _SubjectLibraryScreenState();
}

class _SubjectLibraryScreenState extends State<SubjectLibraryScreen> {
  static const _topicsKey = 'life_rpg_study_topics_v1';
  static const _documentsKey = 'life_rpg_subject_documents_v1';
  final ImagePicker _imagePicker = ImagePicker();
  final TopicExtractor _extractor = const TopicExtractor();
  final Map<String, List<StudyTopic>> _topics = {};
  final List<_SubjectDocument> _documents = [];
  bool _loading = true;
  String? _processingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawTopics = prefs.getString(_topicsKey);
      if (rawTopics != null) {
        final decoded = jsonDecode(rawTopics) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _topics[entry.key] = (entry.value as List<dynamic>)
              .map((item) => StudyTopic.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
      final rawDocs = prefs.getString(_documentsKey);
      if (rawDocs != null) {
        final decoded = jsonDecode(rawDocs) as List<dynamic>;
        _documents.addAll(decoded
            .map((item) => _SubjectDocument.fromJson(item as Map<String, dynamic>))
            .where((item) => File(item.path).existsSync()));
      }
    } catch (_) {
      // Keep the rest of the local library available if an old entry is damaged.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_topicsKey, jsonEncode(_topics.map(
      (key, value) => MapEntry(key, value.map((topic) => topic.toJson()).toList()),
    )));
    await prefs.setString(_documentsKey,
        jsonEncode(_documents.map((doc) => doc.toJson()).toList()));
  }

  List<StudyTopic> _subjectTopics(String subjectId) =>
      _topics.putIfAbsent(subjectId, () => <StudyTopic>[]);

  List<_SubjectDocument> _subjectDocuments(String subjectId) =>
      _documents.where((doc) => doc.subjectId == subjectId).toList();

  Future<void> _openSubject(SubjectSection subject) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SubjectDetailPage(
        subject: subject,
        topics: _subjectTopics(subject.id),
        documents: () => _subjectDocuments(subject.id),
        onImport: (kind, camera) => _import(subject, kind, camera: camera),
        onEditTopics: () => _editTopics(subject),
        onOpenTopic: (topic) => _openTopic(subject, topic),
        onEditTopic: _editTopic,
        onDeleteTopic: _deleteTopic,
        onOpenDocument: _openDocument,
        onReadDocument: _readDocument,
        onDeleteDocument: _deleteDocument,
        processingId: () => _processingId,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _import(SubjectSection subject, String kind,
      {bool camera = false}) async {
    String? sourcePath;
    String originalName = '';
    if (kind == 'pdf') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.single.path == null) return;
      sourcePath = result.files.single.path;
      originalName = result.files.single.name;
    } else {
      final photo = await _imagePicker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
      if (photo == null) return;
      sourcePath = photo.path;
      originalName = photo.name;
    }

    if (!mounted) return;
    final titleController = TextEditingController(text: originalName);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Agregar a ${subject.title}'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del material'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (accepted != true || sourcePath == null || !mounted) {
      titleController.dispose();
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/subject_materials');
      if (!await folder.exists()) await folder.create(recursive: true);
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final dot = originalName.lastIndexOf('.');
      final extension = dot >= 0 ? originalName.substring(dot) : (kind == 'image' ? '.jpg' : '.pdf');
      final path = '${folder.path}/$id$extension';
      await File(sourcePath).copy(path);
      final doc = _SubjectDocument(
        id: id,
        subjectId: subject.id,
        title: titleController.text.trim().isEmpty ? originalName : titleController.text.trim(),
        path: path,
        kind: kind,
      );
      _documents.insert(0, doc);
      await _save();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Material guardado en esta materia.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el archivo: $error')),
        );
      }
    } finally {
      titleController.dispose();
    }
  }

  Future<String> _extract(_SubjectDocument doc) async {
    if (doc.extractedText != null) return doc.extractedText!;
    if (doc.kind == 'pdf') {
      PdfDocument? pdf;
      try {
        pdf = PdfDocument(inputBytes: await File(doc.path).readAsBytes());
        doc.extractedText = PdfTextExtractor(pdf).extractText().trim();
      } finally {
        pdf?.dispose();
      }
    } else {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(doc.path));
        doc.extractedText = result.text.trim();
      } finally {
        await recognizer.close();
      }
    }
    await _save();
    return doc.extractedText ?? '';
  }

  Future<void> _readDocument(_SubjectDocument doc) async {
    if (_processingId != null) return;
    setState(() => _processingId = doc.id);
    try {
      final text = await _extract(doc);
      if (!mounted) return;
      final controller = TextEditingController(text: text);
      final saveText = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Texto leído · ${doc.title}'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: controller,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText: 'Podés corregir errores del reconocimiento antes de guardar.',
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cerrar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar texto')),
          ],
        ),
      );
      if (saveText == true) {
        doc.extractedText = controller.text.trim();
        await _save();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Texto guardado. Ahora podés proponer temas desde este material.')),
          );
        }
      }
      controller.dispose();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo leer el material: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _openDocument(_SubjectDocument doc) async {
    if (doc.kind == 'image') {
      await showDialog<void>(context: context, builder: (ctx) => Dialog(
        child: InteractiveViewer(child: Image.file(File(doc.path), fit: BoxFit.contain)),
      ));
    } else {
      // A preview of the PDF can be added separately; text extraction is available now.
      await _readDocument(doc);
    }
  }

  Future<void> _deleteDocument(_SubjectDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar material'),
        content: Text('¿Querés eliminar "${doc.title}" de esta materia?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;
    _documents.removeWhere((item) => item.id == doc.id);
    for (final topics in _topics.values) {
      for (final topic in topics) {
        topic.sourceDocumentIds.remove(doc.id);
      }
    }
    try { await File(doc.path).delete(); } catch (_) {}
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _editTopics(SubjectSection subject) async {
    final topics = _subjectTopics(subject.id);
    final material = _subjectDocuments(subject.id)
        .where((doc) => (doc.extractedText ?? '').trim().isNotEmpty)
        .toList();
    if (material.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero leé el texto de un PDF o una foto para poder detectar títulos.')),
      );
      return;
    }
    final combined = material.map((doc) => doc.extractedText!).join('\n');
    final suggestions = _extractor.extract(combined);
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No encontré títulos claros. Podés agregar los temas manualmente.')),
      );
    }
    final selected = <String>{};
    if (suggestions.isNotEmpty) {
      selected.addAll(suggestions.map((item) => item.title));
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
          title: const Text('Temas sugeridos'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Son títulos detectados por su formato (numeración, Unidad/Tema o mayúsculas). Revisalos: no es una interpretación inteligente del contenido.'),
                const SizedBox(height: 10),
                ...suggestions.map((suggestion) => CheckboxListTile(
                  value: selected.contains(suggestion.title),
                  title: Text(suggestion.title),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => refresh(() {
                    if (value == true) { selected.add(suggestion.title); }
                    else { selected.remove(suggestion.title); }
                  }),
                )),
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar seleccionados')),
          ],
        )),
      );
      if (accepted != true) return;
    }
    for (final title in selected) {
      final exists = topics.any((topic) => topic.title.toLowerCase() == title.toLowerCase());
      if (!exists) {
        topics.add(StudyTopic(
          id: DateTime.now().microsecondsSinceEpoch.toString() + title.hashCode.toString(),
          title: title,
          sourceDocumentIds: material.map((doc) => doc.id).toList(),
        ));
      }
    }
    await _manualTopic(subject);
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _manualTopic(SubjectSection subject) async {
    final controller = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar tema manualmente'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del tema'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (add == true && controller.text.trim().isNotEmpty) {
      final title = controller.text.trim();
      if (!_subjectTopics(subject.id).any((item) => item.title.toLowerCase() == title.toLowerCase())) {
        _subjectTopics(subject.id).add(StudyTopic(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
        ));
      }
      await _save();
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  Future<void> _editTopic(StudyTopic topic) async {
    final controller = TextEditingController(text: topic.title);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar tema'),
        content: TextField(controller: controller, autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del tema')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (saved == true && controller.text.trim().isNotEmpty) {
      topic.title = controller.text.trim();
      await _save();
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  Future<void> _deleteTopic(StudyTopic topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tema'),
        content: Text('¿Querés eliminar "' + topic.title + '" y su progreso? Los documentos originales no se borran.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed == true) {
      for (final list in _topics.values) {
        list.removeWhere((item) => item.id == topic.id);
      }
      await _save();
      if (mounted) setState(() {});
    }
  }

  Future<void> _openTopic(SubjectSection subject, StudyTopic topic) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _TopicDetailPage(
        subject: subject,
        topic: topic,
        documents: _subjectDocuments(subject.id)
            .where((doc) => topic.sourceDocumentIds.isEmpty || topic.sourceDocumentIds.contains(doc.id))
            .toList(),
        onSave: () async { await _save(); if (mounted) setState(() {}); },
        onRead: _readDocument,
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Materias', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('Cada materia reúne sus documentos, temas y niveles de comprensión.'),
        const SizedBox(height: 16),
        ...SubjectSection.defaults.map((subject) {
          final docs = _subjectDocuments(subject.id).length;
          final topics = _subjectTopics(subject.id);
          final mastered = topics.where((topic) => topic.achievedStage == 4).length;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(child: Icon(_subjectIcon(subject.iconKey))),
              title: Text(subject.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('$docs documentos · ${topics.length} temas · $mastered integrados'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openSubject(subject),
            ),
          );
        }),
      ],
    );
  }

  IconData _subjectIcon(String key) => switch (key) {
    'physics' => Icons.science_outlined,
    'analysis' => Icons.functions,
    'algebra' => Icons.grid_4x4,
    _ => Icons.biotech_outlined,
  };
}

class _SubjectDetailPage extends StatefulWidget {
  final SubjectSection subject;
  final List<StudyTopic> topics;
  final List<_SubjectDocument> Function() documents;
  final Future<void> Function(String kind, bool camera) onImport;
  final Future<void> Function() onEditTopics;
  final Future<void> Function(StudyTopic topic) onOpenTopic;
  final Future<void> Function(StudyTopic topic) onEditTopic;
  final Future<void> Function(StudyTopic topic) onDeleteTopic;
  final Future<void> Function(_SubjectDocument doc) onOpenDocument;
  final Future<void> Function(_SubjectDocument doc) onReadDocument;
  final Future<void> Function(_SubjectDocument doc) onDeleteDocument;
  final String? Function() processingId;

  const _SubjectDetailPage({
    required this.subject,
    required this.topics,
    required this.documents,
    required this.onImport,
    required this.onEditTopics,
    required this.onOpenTopic,
    required this.onEditTopic,
    required this.onDeleteTopic,
    required this.onOpenDocument,
    required this.onReadDocument,
    required this.onDeleteDocument,
    required this.processingId,
  });

  @override
  State<_SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<_SubjectDetailPage> {
  @override
  Widget build(BuildContext context) {
    final documents = widget.documents();
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.subject.description),
          const SizedBox(height: 16),
          Text('Material de estudio', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () async { await widget.onImport('pdf', false); if (mounted) setState(() {}); },
              icon: const Icon(Icons.picture_as_pdf), label: const Text('Subir PDF')),
            OutlinedButton.icon(onPressed: () async { await widget.onImport('image', false); if (mounted) setState(() {}); },
              icon: const Icon(Icons.photo_library_outlined), label: const Text('Elegir foto')),
            OutlinedButton.icon(onPressed: () async { await widget.onImport('image', true); if (mounted) setState(() {}); },
              icon: const Icon(Icons.camera_alt_outlined), label: const Text('Sacar foto')),
          ]),
          const SizedBox(height: 8),
          if (documents.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Todavía no hay documentos en esta materia. Subí un PDF o una foto para empezar.'),
            )),
          ...documents.map((doc) => Card(child: ListTile(
            leading: Icon(doc.kind == 'image' ? Icons.image_outlined : Icons.picture_as_pdf),
            title: Text(doc.title),
            subtitle: Text(doc.extractedText == null ? 'Texto todavía no leído' : 'Texto leído · ${doc.extractedText!.length} caracteres'),
            onTap: () => widget.onOpenDocument(doc),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'read') widget.onReadDocument(doc);
                if (value == 'delete') widget.onDeleteDocument(doc);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'read', child: Text('Leer / editar texto')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Temas', style: Theme.of(context).textTheme.titleLarge)),
            TextButton.icon(onPressed: () async { await widget.onEditTopics(); if (mounted) setState(() {}); },
              icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Detectar / agregar')),
          ]),
          const Text('La detección busca títulos y numeraciones. Siempre podés corregir la lista; no interpreta por sí sola el contenido.'),
          const SizedBox(height: 8),
          if (widget.topics.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Todavía no hay temas. Leé un documento y usá “Detectar / agregar”, o cargá un tema manualmente.'),
            )),
          ...widget.topics.map((topic) => Card(child: ListTile(
            title: Text(topic.title),
            subtitle: Text(topic.currentStageLabel),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'open') widget.onOpenTopic(topic);
                if (value == 'edit') widget.onEditTopic(topic);
                if (value == 'delete') widget.onDeleteTopic(topic);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Abrir niveles')),
                PopupMenuItem(value: 'edit', child: Text('Editar nombre')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar tema')),
              ],
            ),
            onTap: () => widget.onOpenTopic(topic),
          ))),
        ],
      ),
    );
  }
}

class _TopicDetailPage extends StatefulWidget {
  final SubjectSection subject;
  final StudyTopic topic;
  final List<_SubjectDocument> documents;
  final Future<void> Function() onSave;
  final Future<void> Function(_SubjectDocument doc) onRead;

  const _TopicDetailPage({
    required this.subject,
    required this.topic,
    required this.documents,
    required this.onSave,
    required this.onRead,
  });

  @override
  State<_TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<_TopicDetailPage> {
  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    return Scaffold(
      appBar: AppBar(title: Text(topic.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.subject.title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text('Progreso de comprensión', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: topic.achievedStage / 4),
          const SizedBox(height: 6),
          Text('${topic.achievedStage} de 4 niveles registrados'),
          const SizedBox(height: 16),
          ...MasteryStage.values.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final stage = entry.value;
            final achieved = topic.achievedStage >= index;
            return Card(
              child: ExpansionTile(
                leading: Icon(achieved ? Icons.check_circle : Icons.circle_outlined,
                  color: achieved ? Colors.green : null),
                title: Text(stage.title),
                subtitle: Text(stage.description),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(_stagePrompt(index)),
                  if (widget.documents.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Material relacionado', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    ...widget.documents.map((doc) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(doc.title),
                      trailing: IconButton(
                        icon: const Icon(Icons.text_snippet_outlined),
                        onPressed: () => widget.onRead(doc),
                      ),
                    )),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: achieved || index != topic.achievedStage + 1
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Registrar nivel'),
                                  content: const Text('Esto registra tu autoevaluación, no una prueba automática. Más adelante cada nivel tendrá una evaluación para comprobarlo. ¿Querés continuar?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                setState(() => topic.achievedStage = index);
                                await widget.onSave();
                              }
                            },
                      child: Text(achieved ? 'Nivel registrado' : 'Registrar como alcanzado'),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _stagePrompt(int index) => switch (index) {
    1 => 'Comprobá que podés reconocer los conceptos, símbolos, magnitudes y definiciones cuando aparecen en el material.',
    2 => 'Intentá explicar con tus palabras qué significa cada idea y por qué sucede. No alcanza con repetir la definición.',
    3 => 'Resolvé ejercicios usando el concepto y justificá por qué elegís ese procedimiento.',
    _ => 'Relacioná este tema con otros y resolvé una situación nueva sin depender de una receta conocida.',
  };
}

class _SubjectDocument {
  final String id;
  final String subjectId;
  final String title;
  final String path;
  final String kind;
  String? extractedText;

  _SubjectDocument({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.path,
    required this.kind,
    this.extractedText,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'path': path,
    'kind': kind,
    'extractedText': extractedText,
  };

  factory _SubjectDocument.fromJson(Map<String, dynamic> json) => _SubjectDocument(
    id: json['id'] as String,
    subjectId: json['subjectId'] as String,
    title: json['title'] as String? ?? 'Material',
    path: json['path'] as String,
    kind: json['kind'] as String? ?? 'pdf',
    extractedText: json['extractedText'] as String?,
  );
}
