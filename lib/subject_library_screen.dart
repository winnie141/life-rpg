import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import 'study_structure.dart';
import 'topic_learning_content.dart';

class SubjectLibraryScreen extends StatefulWidget {
  const SubjectLibraryScreen({super.key});

  @override
  State<SubjectLibraryScreen> createState() => _SubjectLibraryScreenState();
}

class _SubjectLibraryScreenState extends State<SubjectLibraryScreen> {
  static const _topicsKey = 'life_rpg_study_topics_v1';
  static const _documentsKey = 'life_rpg_subject_documents_v1';
  final ImagePicker _imagePicker = ImagePicker();
  final ProgramTopicParser _programParser = const ProgramTopicParser();
  final TopicExtractor _topicExtractor = const TopicExtractor();
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
            .where((item) => item.kind == 'text' || (item.path.isNotEmpty && File(item.path).existsSync())));
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
        onImport: (kind, category, camera) => _import(subject, kind, category, camera: camera),
        onAddProgramText: () => _addProgramText(subject),
        onAnalyze: () => _analyzeSubject(subject),
        onEditDocument: _editDocument,
        onAddManualTopic: () => _manualTopic(subject),
        onOpenTopic: (topic) => _openTopic(subject, topic),
        onEditTopic: _editTopic,
        onDeleteTopic: _deleteTopic,
        onOpenDocument: _openDocument,
        onReadDocument: _readDocument,
        onDeleteDocument: _deleteDocument,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _import(SubjectSection subject, String kind, String category,
      {bool camera = false}) async {
    String? sourcePath;
    String originalName = '';
    if (kind == 'pdf') {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
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
    final sectionController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_categoryTitle(category)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleController, autofocus: true,
            decoration: const InputDecoration(labelText: 'Título del archivo')),
          if (category != 'program') ...[
            const SizedBox(height: 12),
            TextField(controller: sectionController,
              decoration: const InputDecoration(
                labelText: 'Tema o sección relacionada (opcional)',
                hintText: 'Ej.: Integrales definidas')),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (accepted != true || sourcePath == null || !mounted) {
      titleController.dispose();
      sectionController.dispose();
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
      _documents.insert(0, _SubjectDocument(
        id: id, subjectId: subject.id,
        title: titleController.text.trim().isEmpty ? originalName : titleController.text.trim(),
        path: path, kind: kind, category: category,
        section: sectionController.text.trim(),
      ));
      await _save();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_categoryTitle(category)} guardado.')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el archivo: $error')),
      );
    } finally {
      titleController.dispose();
      sectionController.dispose();
    }
  }

  String _categoryTitle(String category) => switch (category) {
    'program' => 'Cargar programa de la materia',
    'guide' => 'Cargar guía o ejercicios',
    _ => 'Cargar material de estudio',
  };

  Future<void> _addProgramText(SubjectSection subject) async {
    final titleController = TextEditingController(text: 'Programa de ${subject.title}');
    final contentController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pegar programa de la materia'),
        content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleController,
            decoration: const InputDecoration(labelText: 'Título del programa')),
          const SizedBox(height: 12),
          TextField(controller: contentController, minLines: 7, maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: 'Temas en orden',
              hintText: '1. Límites\n2. Derivadas\n3. Integrales indefinidas\n4. Integrales definidas',
              helperText: 'Escribí un tema por línea. Se conserva el orden.')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar programa')),
        ],
      ),
    );
    final text = contentController.text.trim();
    if (accepted == true && text.isNotEmpty) {
      _documents.insert(0, _SubjectDocument(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        subjectId: subject.id,
        title: titleController.text.trim().isEmpty ? 'Programa de ${subject.title}' : titleController.text.trim(),
        path: '', kind: 'text', category: 'program', section: '',
        extractedText: text,
      ));
      await _save();
      if (mounted) setState(() {});
    }
    titleController.dispose();
    contentController.dispose();
  }

  Future<void> _editDocument(_SubjectDocument doc) async {
    final titleController = TextEditingController(text: doc.title);
    final sectionController = TextEditingController(text: doc.section);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar documento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Título')),
          if (doc.category != 'program') ...[
            const SizedBox(height: 10),
            TextField(controller: sectionController,
              decoration: const InputDecoration(labelText: 'Tema o sección relacionada')),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (saved == true) {
      doc.title = titleController.text.trim().isEmpty ? doc.title : titleController.text.trim();
      doc.section = sectionController.text.trim();
      await _save();
      if (mounted) setState(() {});
    }
    titleController.dispose();
    sectionController.dispose();
  }

  Future<String> _extract(_SubjectDocument doc) async {
    if (doc.extractedText != null) return doc.extractedText!;
    if (doc.kind == 'text') return '';

    if (doc.kind == 'pdf') {
      PdfDocument? selectablePdf;
      var text = '';
      try {
        selectablePdf = PdfDocument(inputBytes: await File(doc.path).readAsBytes());
        text = PdfTextExtractor(selectablePdf).extractText().trim();
      } finally {
        selectablePdf?.dispose();
      }

      // A scanned PDF has no selectable text. Render its pages and pass each
      // image through ML Kit instead of leaving the document unreadable.
      if (text.isEmpty) {
        text = await _recognizeScannedPdf(doc.path);
      }
      doc.extractedText = text;
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

  Future<String> _recognizeScannedPdf(String path) async {
    pdfx.PdfDocument? document;
    TextRecognizer? recognizer;
    final recognizedPages = <String>[];
    final temporaryFiles = <File>[];
    try {
      document = await pdfx.PdfDocument.openFile(path);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      // Keep processing bounded so a very large scan does not freeze the app.
      final pageLimit = document.pagesCount < 40 ? document.pagesCount : 40;
      final tempDirectory = await getTemporaryDirectory();

      for (var pageNumber = 1; pageNumber <= pageLimit; pageNumber++) {
        final page = await document.getPage(pageNumber);
        try {
          final image = await page.render(
            width: (page.width * 2).round(),
            height: (page.height * 2).round(),
            format: pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#ffffff',
          );
          final imageFile = File(
            '${tempDirectory.path}/life_rpg_ocr_${DateTime.now().microsecondsSinceEpoch}_$pageNumber.jpg',
          );
          await imageFile.writeAsBytes(image.bytes, flush: true);
          temporaryFiles.add(imageFile);
          final result = await recognizer.processImage(
            InputImage.fromFilePath(imageFile.path),
          );
          final pageText = result.text.trim();
          if (pageText.isNotEmpty) {
            recognizedPages.add('[Página $pageNumber]\n$pageText');
          }
        } finally {
          await page.close();
        }
      }

      var result = recognizedPages.join('\n\n');
      if (document.pagesCount > pageLimit) {
        result += '\n\n[Se procesaron las primeras $pageLimit páginas de ${document.pagesCount}. El resto quedó sin OCR.]';
      }
      return result;
    } finally {
      for (final file in temporaryFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      await recognizer?.close();
      await document?.close();
    }
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
    if (doc.kind == 'text') {
      await _readDocument(doc);
    } else if (doc.kind == 'image') {
      await showDialog<void>(context: context, builder: (ctx) => Dialog(
        child: InteractiveViewer(child: Image.file(File(doc.path), fit: BoxFit.contain)),
      ));
    } else {
      await OpenFilex.open(doc.path);
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
    if (doc.path.isNotEmpty) { try { await File(doc.path).delete(); } catch (_) {} }
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _analyzeSubject(SubjectSection subject) async {
    final docs = _subjectDocuments(subject.id);
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero cargá apuntes, guías o el programa de la materia.')),
      );
      return;
    }
    if (mounted) setState(() => _processingId = 'analyzing');
    try {
      for (final doc in docs) {
        await _extract(doc);
      }

      final programs = docs.where((doc) => doc.category == 'program').toList();
      final programText = programs.map((doc) => doc.extractedText ?? '')
          .where((value) => value.trim().isNotEmpty).join('\n');
      final programTitles = _programParser.parse(programText);

      // Without an official syllabus, build a provisional structure from
      // explicit headings in the uploaded notes and guides.
      final inferredTitles = <String>[];
      final seenTitles = <String>{};
      for (final doc in docs.where((item) => item.category != 'program')) {
        for (final suggestion in _topicExtractor.extract(doc.extractedText ?? '')) {
          final key = _normalizeMatch(suggestion.title);
          if (key.isNotEmpty && seenTitles.add(key)) inferredTitles.add(suggestion.title);
        }
      }

      final hasProgram = programTitles.isNotEmpty;
      final proposedTitles = hasProgram ? programTitles : inferredTitles;
      final fallbackTitles = <String>[];
      if (proposedTitles.isEmpty) {
        for (final doc in docs.where((item) => item.category != 'program')) {
          final candidate = doc.section.trim().isNotEmpty ? doc.section.trim() : doc.title.trim();
          if (candidate.isNotEmpty &&
              !fallbackTitles.any((value) => _sameText(value, candidate))) {
            fallbackTitles.add(candidate);
          }
        }
      }
      final finalTitles = proposedTitles.isNotEmpty ? proposedTitles : fallbackTitles;
      if (finalTitles.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No encontré temas claros. Revisá que los archivos tengan texto legible o agregá un tema manualmente.')),
        );
        return;
      }

      final topics = _subjectTopics(subject.id);
      final previous = List<StudyTopic>.from(topics);
      final rebuilt = <StudyTopic>[];
      for (final title in finalTitles) {
        StudyTopic? existing;
        for (final candidate in previous) {
          if (_sameText(candidate.title, title)) { existing = candidate; break; }
        }
        rebuilt.add(existing ?? StudyTopic(
          id: DateTime.now().microsecondsSinceEpoch.toString() + rebuilt.length.toString(),
          title: title,
        ));
      }
      // Keep manually created topics and their progress rather than deleting
      // them when a new analysis proposes a shorter list.
      for (final old in previous) {
        if (!rebuilt.any((topic) => topic.id == old.id)) rebuilt.add(old);
      }
      topics..clear()..addAll(rebuilt);
      for (final topic in topics) { topic.sourceDocumentIds.clear(); }

      final unmatched = <_SubjectDocument>[];
      for (final doc in docs.where((item) => item.category != 'program')) {
        final section = _normalizeMatch(doc.section);
        final extracted = _normalizeMatch(doc.extractedText ?? '');
        final titleText = _normalizeMatch(doc.title);
        final matches = topics.where((topic) {
          final title = _normalizeMatch(topic.title);
          if (title.isEmpty) return false;
          if (section.isNotEmpty && section == title) return true;
          if (titleText == title) return true;
          return extracted.contains(title);
        }).toList();
        if (matches.isEmpty) {
          unmatched.add(doc);
        } else {
          for (final topic in matches) {
            if (!topic.sourceDocumentIds.contains(doc.id)) {
              topic.sourceDocumentIds.add(doc.id);
            }
          }
        }
      }
      await _save();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Análisis terminado'),
          content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hasProgram
                ? '${finalTitles.length} temas organizados según el programa.'
                : '${finalTitles.length} temas provisorios detectados a partir de tus archivos.'),
              const SizedBox(height: 12),
              const Text('Documentos relacionados:', style: TextStyle(fontWeight: FontWeight.w600)),
              ...topics.map((topic) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• ${topic.title}: ${topic.sourceDocumentIds.length} documento(s)'),
              )),
              if (unmatched.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Sin asociación automática (podés editar su sección):', style: TextStyle(fontWeight: FontWeight.w600)),
                ...unmatched.map((doc) => Text('• ${doc.title}')),
              ],
              const SizedBox(height: 12),
              Text(hasProgram
                ? 'El programa define el orden. Las asociaciones se basan en secciones y coincidencias de texto; revisá los resultados.'
                : 'La estructura es provisoria: se detectaron encabezados o se usaron los títulos de tus archivos. Cuando agregues el programa oficial, volvé a analizar para ordenar los temas. La asociación no es una interpretación semántica completa.'),
            ]),
          )),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Aceptar'))],
        ),
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo analizar la materia: $error')),
      );
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  bool _sameText(String a, String b) => _normalizeMatch(a) == _normalizeMatch(b);

  String _normalizeMatch(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[^a-záéíóúüñ0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();

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
            .where((doc) => topic.sourceDocumentIds.contains(doc.id))
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
  final Future<void> Function(String kind, String category, bool camera) onImport;
  final Future<void> Function() onAddProgramText;
  final Future<void> Function() onAnalyze;
  final Future<void> Function(_SubjectDocument doc) onEditDocument;
  final Future<void> Function() onAddManualTopic;
  final Future<void> Function(StudyTopic topic) onOpenTopic;
  final Future<void> Function(StudyTopic topic) onEditTopic;
  final Future<void> Function(StudyTopic topic) onDeleteTopic;
  final Future<void> Function(_SubjectDocument doc) onOpenDocument;
  final Future<void> Function(_SubjectDocument doc) onReadDocument;
  final Future<void> Function(_SubjectDocument doc) onDeleteDocument;

  const _SubjectDetailPage({
    required this.subject, required this.topics, required this.documents,
    required this.onImport, required this.onAddProgramText, required this.onAnalyze,
    required this.onEditDocument, required this.onAddManualTopic,
    required this.onOpenTopic, required this.onEditTopic, required this.onDeleteTopic,
    required this.onOpenDocument, required this.onReadDocument, required this.onDeleteDocument,
  });

  @override
  State<_SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<_SubjectDetailPage> {
  Widget _uploadSection({
    required String title,
    required String description,
    required List<_SubjectDocument> docs,
    required List<Widget> buttons,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(description),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
          if (docs.isNotEmpty) ...[
            const Divider(height: 20),
            ...docs.map((doc) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(doc.kind == 'image' ? Icons.image_outlined : doc.kind == 'text' ? Icons.subject : Icons.picture_as_pdf),
              title: Text(doc.title),
              subtitle: Text([
                if (doc.section.isNotEmpty) doc.section,
                if (doc.extractedText == null) 'Texto todavía no leído'
                else 'Texto leído · ${doc.extractedText!.length} caracteres',
              ].join(' · ')),
              onTap: () async { await widget.onOpenDocument(doc); if (mounted) setState(() {}); },
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'read') await widget.onReadDocument(doc);
                  if (value == 'edit') await widget.onEditDocument(doc);
                  if (value == 'delete') await widget.onDeleteDocument(doc);
                  if (mounted) setState(() {});
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'read', child: Text('Leer / editar texto')),
                  PopupMenuItem(value: 'edit', child: Text('Editar título / sección')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
            )),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = widget.documents();
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.subject.description),
          const SizedBox(height: 18),
          _uploadSection(
            title: '1. Programa de la materia',
            description: 'Define el orden y la estructura de los temas.',
            docs: documents.where((doc) => doc.category == 'program').toList(),
            buttons: [
              FilledButton.icon(
                onPressed: () async { await widget.onImport('pdf', 'program', false); if (mounted) setState(() {}); },
                icon: const Icon(Icons.picture_as_pdf), label: const Text('Subir programa PDF')),
              OutlinedButton.icon(
                onPressed: () async { await widget.onImport('image', 'program', false); if (mounted) setState(() {}); },
                icon: const Icon(Icons.photo_library_outlined), label: const Text('Foto')),
              TextButton.icon(
                onPressed: () async { await widget.onAddProgramText(); if (mounted) setState(() {}); },
                icon: const Icon(Icons.edit_note), label: const Text('Pegar temas en orden')),
            ],
          ),
          _uploadSection(
            title: '2. Material de estudio',
            description: 'Apuntes, libros, capítulos y resúmenes.',
            docs: documents.where((doc) => doc.category == 'material').toList(),
            buttons: [
              FilledButton.icon(
                onPressed: () async { await widget.onImport('pdf', 'material', false); if (mounted) setState(() {}); },
                icon: const Icon(Icons.picture_as_pdf), label: const Text('Subir PDF')),
              OutlinedButton.icon(
                onPressed: () async { await widget.onImport('image', 'material', false); if (mounted) setState(() {}); },
                icon: const Icon(Icons.photo_library_outlined), label: const Text('Foto')),
              OutlinedButton.icon(
                onPressed: () async { await widget.onImport('image', 'material', true); if (mounted) setState(() {}); },
                icon: const Icon(Icons.camera_alt_outlined), label: const Text('Cámara')),
            ],
          ),
          _uploadSection(
            title: '3. Guías y ejercicios',
            description: 'Trabajos prácticos, ejercicios resueltos y parciales anteriores.',
            docs: documents.where((doc) => doc.category == 'guide').toList(),
            buttons: [
              FilledButton.icon(
                onPressed: () async { await widget.onImport('pdf', 'guide', false); if (mounted) setState(() {}); },
                icon: const Icon(Icons.picture_as_pdf), label: const Text('Subir guía PDF')),
              OutlinedButton.icon(
                onPressed: () async { await widget.onImport('image', 'guide', false); if (mounted) setState(() {}); },
                icon: const Icon(Icons.photo_library_outlined), label: const Text('Foto')),
              OutlinedButton.icon(
                onPressed: () async { await widget.onImport('image', 'guide', true); if (mounted) setState(() {}); },
                icon: const Icon(Icons.camera_alt_outlined), label: const Text('Cámara')),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: documents.isNotEmpty ? () async {
                await widget.onAnalyze();
                if (mounted) setState(() {});
              } : null,
              icon: const Icon(Icons.auto_awesome), label: const Text('Analizar materia')),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Text('Temas del programa', style: Theme.of(context).textTheme.titleLarge)),
            TextButton.icon(
              onPressed: () async { await widget.onAddManualTopic(); if (mounted) setState(() {}); },
              icon: const Icon(Icons.add), label: const Text('Agregar tema')),
          ]),
          const SizedBox(height: 8),
          const Text('El programa establece el orden. Los documentos se asocian por la sección que indiques o por coincidencias claras del título. Revisá siempre el resultado.'),
          const SizedBox(height: 8),
          if (widget.topics.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Todavía no hay temas. Cargá apuntes o guías y tocá “Analizar materia”. El programa oficial es opcional: sin él se crea una estructura provisoria.'),
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
    required this.subject, required this.topic, required this.documents,
    required this.onSave, required this.onRead,
  });

  @override
  State<_TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<_TopicDetailPage> {
  static const _content = TopicLearningContent();
  final TextEditingController _answerController = TextEditingController();
  bool _showReference = false;

  List<_SubjectDocument> get _withText => widget.documents
      .where((doc) => (doc.extractedText ?? '').trim().isNotEmpty).toList();

  List<StudyTextSection> _sections(_SubjectDocument doc) =>
      _content.sections(doc.extractedText ?? '');

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Widget _header() {
    final topic = widget.topic;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.subject.title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(topic.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: LinearProgressIndicator(value: topic.achievedStage / 4)),
          const SizedBox(width: 12),
          Text(topic.achievedStage.toString() + '/4'),
        ]),
        const SizedBox(height: 6),
        Text(topic.achievedStage == 4 ? 'Tema integrado' :
          topic.achievedStage == 0 ? 'Empezá por aprender el contenido' :
          'Último nivel registrado: ' + topic.currentStageLabel),
        const SizedBox(height: 8),
        Text(widget.documents.length.toString() + ' material(es) asociado(s) · ' +
          _withText.length.toString() + ' con texto disponible',
          style: Theme.of(context).textTheme.bodySmall),
      ]),
    ));
  }

  Widget _empty(String message) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.menu_book_outlined, size: 30),
      const SizedBox(height: 8),
      Text(message),
      const SizedBox(height: 8),
      const Text('Volvé a la materia y asociá un apunte o una guía a este tema. Si ya está asociado, usá “Leer / editar texto” para extraer el texto del PDF o de la foto.'),
    ]),
  ));

  Widget _learn() {
    if (widget.documents.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _header(), _empty('Este tema todavía no tiene documentos asociados.'),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _header(),
      const Text('Leé el material de a poco. La app conserva el texto original y lo separa en fragmentos para estudiar sin perder la fuente.',
        style: TextStyle(height: 1.4)),
      const SizedBox(height: 12),
      ...widget.documents.map((doc) {
        final parts = _sections(doc);
        return Card(child: ExpansionTile(
          initiallyExpanded: widget.documents.length == 1,
          leading: Icon(doc.category == 'guide' ? Icons.assignment_outlined : Icons.menu_book_outlined),
          title: Text(doc.title),
          subtitle: Text(parts.isEmpty ? 'Texto pendiente de extracción' :
            parts.length.toString() + ' fragmento(s) de material'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: parts.isEmpty ? [
            const Align(alignment: Alignment.centerLeft, child: Text(
              'No hay texto extraído. Si es un PDF escaneado o una foto, el reconocimiento puede necesitar correcciones.')),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              onPressed: () async { await widget.onRead(doc); if (mounted) setState(() {}); },
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Leer y preparar material'))),
          ] : parts.map((part) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fragmento ' + part.index.toString(),
                style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SelectableText(part.text),
            ]),
          )).toList(),
        ));
      }),
    ]);
  }

  Widget _understand() {
    if (_withText.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _header(), _empty('Para trabajar la comprensión primero necesitamos texto extraído del material.'),
      ]);
    }
    final parts = _withText.expand((doc) =>
      _sections(doc).map((part) => (doc: doc, part: part))).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _header(),
      const Text('No busques repetir el apunte. Intentá reconstruir la idea y explicar qué significa.',
        style: TextStyle(height: 1.4)),
      const SizedBox(height: 12),
      ...parts.map((item) => Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.doc.title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SelectableText(item.part.text),
          const Divider(height: 22),
          const Text('Ahora respondé sin copiar:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('• ¿Cuál es la idea principal?\n• ¿Qué significa con tus palabras?\n• ¿Qué condición, causa o relación menciona?\n• ¿Cómo lo reconocerías en un ejercicio?'),
        ]),
      ))),
    ]);
  }

  Widget _practice() {
    if (_withText.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _header(), _empty('Todavía no hay texto de guías o apuntes para preparar la práctica.'),
      ]);
    }
    final exercises = <({String title, String excerpt})>[];
    for (final doc in _withText) {
      for (final excerpt in _content.practiceExcerpts(doc.extractedText ?? '')) {
        exercises.add((title: doc.title, excerpt: excerpt));
      }
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      _header(),
      const Text('Busco consignas reconocibles dentro de tus archivos. Las pistas ayudan a organizar el razonamiento, pero no reemplazan la resolución.',
        style: TextStyle(height: 1.4)),
      const SizedBox(height: 12),
      if (exercises.isEmpty)
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.search_off, size: 30),
            const SizedBox(height: 8),
            const Text('No encontré consignas identificables automáticamente en el texto extraído.',
              style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('No voy a inventar ejercicios y atribuirlos a tu guía. Elegí un ejemplo o problema del material y seguí esta secuencia:'),
            const SizedBox(height: 8),
            const Text('1. ¿Qué datos tengo y qué me piden?\n2. ¿Qué concepto conecta esos datos con lo que busco?\n3. ¿Por qué corresponde ese procedimiento?\n4. ¿El resultado tiene sentido?'),
          ]),
        ))
      else
        ...exercises.map((exercise) => Card(child: ExpansionTile(
          leading: const Icon(Icons.calculate_outlined),
          title: Text(exercise.title),
          subtitle: const Text('Consigna encontrada en tu material'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(alignment: Alignment.centerLeft, child: SelectableText(exercise.excerpt)),
            const SizedBox(height: 10),
            const ExpansionTile(tilePadding: EdgeInsets.zero,
              title: Text('Pista 1 · Interpretar'),
              children: [Padding(padding: EdgeInsets.only(bottom: 10),
                child: Text('Separá los datos conocidos de lo que te piden. Todavía no elijas una fórmula.'))]),
            const ExpansionTile(tilePadding: EdgeInsets.zero,
              title: Text('Pista 2 · Conectar'),
              children: [Padding(padding: EdgeInsets.only(bottom: 10),
                child: Text('Buscá qué definición, ley o procedimiento del material relaciona esos datos.'))]),
            const ExpansionTile(tilePadding: EdgeInsets.zero,
              title: Text('Pista 3 · Justificar'),
              children: [Padding(padding: EdgeInsets.only(bottom: 10),
                child: Text('Explicá por qué cada paso es válido y verificá unidades, condiciones y resultado.'))]),
          ],
        ))),
    ]);
  }

  Widget _independent() => ListView(padding: const EdgeInsets.all(16), children: [
    _header(),
    const Text('Desafío independiente', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
    const SizedBox(height: 8),
    const Text('Elegí una consigna de la guía o una idea importante del apunte. Intentá resolverla o explicarla sin mirar el procedimiento.',
      style: TextStyle(height: 1.4)),
    const SizedBox(height: 12),
    TextField(controller: _answerController, minLines: 7, maxLines: 14,
      decoration: const InputDecoration(
        border: OutlineInputBorder(), alignLabelWithHint: true,
        labelText: 'Tu razonamiento / resolución',
        hintText: 'Anotá qué identificaste, qué principio usaste y por qué...')),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: () => setState(() => _showReference = !_showReference),
      icon: Icon(_showReference ? Icons.visibility_off : Icons.menu_book_outlined),
      label: Text(_showReference ? 'Ocultar material de referencia' : 'Comparar con el material')),
    if (_showReference) ...[
      const SizedBox(height: 8),
      if (_withText.isEmpty) _empty('No hay texto extraído para mostrar.')
      else ..._withText.map((doc) => Card(child: ExpansionTile(
        title: Text(doc.title),
        children: _sections(doc).map((part) =>
          Padding(padding: const EdgeInsets.all(12), child: SelectableText(part.text))).toList(),
      ))),
    ],
    const SizedBox(height: 12),
    const Text('Revisá: ¿podés justificar cada paso?, ¿usaste una idea que aparece en el material?, ¿podrías repetir el razonamiento sin ayuda?',
      style: TextStyle(height: 1.4)),
  ]);

  Future<void> _evaluate() async {
    final topic = widget.topic;
    if (_withText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Primero necesitás texto de estudio asociado a este tema.')));
      return;
    }
    final next = topic.achievedStage + 1;
    if (next > 4) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Comprobar: ' + MasteryStage.values[next - 1].title),
        content: const Text('Después de estudiar y practicar, ¿cómo pudiste resolver el desafío sin mirar la respuesta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'example'),
            child: const Text('Necesité un ejemplo')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'hints'),
            child: const Text('Con algunas pistas')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'independent'),
            child: const Text('Por mi cuenta')),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (result == 'independent') {
      setState(() => topic.achievedStage = next);
      await widget.onSave();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(MasteryStage.values[next - 1].title + ' registrado.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result == 'hints'
          ? 'Bien: ya estás cerca. Repetí el desafío reduciendo las pistas.'
          : 'Volvé a Aprender y Practicar con un ejemplo del material. Después intentá resolverlo sin mirar.')));
    }
  }

  Widget _evaluation() {
    final topic = widget.topic;
    final completed = topic.achievedStage >= 4;
    final next = completed ? null : MasteryStage.values[topic.achievedStage];
    return ListView(padding: const EdgeInsets.all(16), children: [
      _header(),
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(completed ? '¡Tema integrado!' : 'Siguiente objetivo',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (completed)
            const Text('Completaste los cuatro niveles. Podés volver a practicar para mantenerlo activo.')
          else ...[
            Text(next!.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(next.description),
            const SizedBox(height: 12),
            Text(switch (topic.achievedStage) {
              0 => 'Reconocé los conceptos, símbolos y definiciones cuando aparecen en el material.',
              1 => 'Explicá qué significa la idea y por qué funciona, sin repetir literalmente el apunte.',
              2 => 'Resolvé una consigna de la guía justificando el procedimiento.',
              _ => 'Relacioná este tema con otros y resolvé una situación nueva sin depender de una receta.',
            }),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _evaluate,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Evaluar mi comprensión'))),
            const SizedBox(height: 8),
            const Text('El avance se registra cuando indicás que pudiste hacerlo por tu cuenta. La app no finge corregir respuestas abiertas automáticamente.',
              style: TextStyle(fontSize: 12)),
          ],
        ]),
      )),
      const SizedBox(height: 8),
      ...MasteryStage.values.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final achieved = topic.achievedStage >= index;
        return ListTile(
          leading: Icon(achieved ? Icons.check_circle : Icons.radio_button_unchecked,
            color: achieved ? Colors.green : null),
          title: Text(entry.value.title),
          subtitle: Text(entry.value.description),
          trailing: Text(achieved ? 'Logrado' : index.toString() + '/4'),
        );
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.topic.title),
        bottom: const TabBar(isScrollable: true, tabs: [
          Tab(icon: Icon(Icons.menu_book_outlined), text: 'Aprender'),
          Tab(icon: Icon(Icons.psychology_outlined), text: 'Entender'),
          Tab(icon: Icon(Icons.calculate_outlined), text: 'Practicar'),
          Tab(icon: Icon(Icons.edit_note), text: 'Resolver solo'),
          Tab(icon: Icon(Icons.flag_outlined), text: 'Evaluar'),
        ])),
      body: TabBarView(children: [
        _learn(), _understand(), _practice(), _independent(), _evaluation(),
      ]),
    ),
  );
}

class _SubjectDocument {
  final String id;
  final String subjectId;
  String title;
  final String path;
  final String kind;
  String category;
  String section;
  String? extractedText;

  _SubjectDocument({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.path,
    required this.kind,
    this.category = 'material',
    this.section = '',
    this.extractedText,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'path': path,
    'kind': kind,
    'category': category,
    'section': section,
    'extractedText': extractedText,
  };

  factory _SubjectDocument.fromJson(Map<String, dynamic> json) => _SubjectDocument(
    id: json['id'] as String,
    subjectId: json['subjectId'] as String,
    title: json['title'] as String? ?? 'Material',
    path: json['path'] as String,
    kind: json['kind'] as String? ?? 'pdf',
    category: json['category'] as String? ?? 'material',
    section: json['section'] as String? ?? '',
    extractedText: json['extractedText'] as String?,
  );
}
