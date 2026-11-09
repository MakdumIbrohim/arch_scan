import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../models/document_model.dart';

class DocumentStorageService {
  static final DocumentStorageService instance = DocumentStorageService._();
  DocumentStorageService._();

  Directory? _appDir;

  Future<Directory> get appDirectory async {
    if (_appDir != null) return _appDir!;
    try {
      _appDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      // Fallback for desktop test environment
      final dir = Directory('.arch_scan_data');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _appDir = dir;
    }
    return _appDir!;
  }

  Future<File> get _indexFile async {
    final dir = await appDirectory;
    return File('${dir.path}/documents.json');
  }

  Future<List<ScanDocument>> loadDocuments() async {
    try {
      final file = await _indexFile;
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> list = jsonDecode(content);
      final docs = list.map((item) => ScanDocument.fromJson(item as Map<String, dynamic>)).toList();
      // Sort newest first
      docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return docs;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading documents: $e');
      return [];
    }
  }

  Future<void> saveDocument(ScanDocument doc) async {
    final docs = await loadDocuments();
    final idx = docs.indexWhere((d) => d.id == doc.id);
    if (idx >= 0) {
      docs[idx] = doc;
    } else {
      docs.insert(0, doc);
    }
    await _writeDocuments(docs);
  }

  Future<void> deleteDocument(String id) async {
    final docs = await loadDocuments();
    final toDelete = docs.where((d) => d.id == id).toList();
    for (final doc in toDelete) {
      // Delete page files
      for (final p in doc.pages) {
        try {
          final fRaw = File(p.rawImagePath);
          if (fRaw.existsSync()) fRaw.deleteSync();
          final fProc = File(p.processedImagePath);
          if (fProc.existsSync()) fProc.deleteSync();
        } catch (_) {}
      }
      if (doc.pdfPath != null) {
        try {
          final fPdf = File(doc.pdfPath!);
          if (fPdf.existsSync()) fPdf.deleteSync();
        } catch (_) {}
      }
    }

    docs.removeWhere((d) => d.id == id);
    await _writeDocuments(docs);
  }

  Future<void> _writeDocuments(List<ScanDocument> docs) async {
    final file = await _indexFile;
    final jsonString = jsonEncode(docs.map((d) => d.toJson()).toList());
    await file.writeAsString(jsonString);
  }

  Future<String?> generatePdfForDocument(ScanDocument doc) async {
    if (doc.pages.isEmpty) return null;

    final dir = await appDirectory;
    final pdfDir = Directory('${dir.path}/pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }

    final outPath = '${pdfDir.path}/${doc.id}.pdf';
    final imagePaths = doc.pages.map((p) => p.processedImagePath).toList();

    final success = ArchScanBridge.instance.generatePdf(
      imagePaths: imagePaths,
      outputPdfPath: outPath,
    );

    if (success) {
      doc.pdfPath = outPath;
      doc.updatedAt = DateTime.now();
      await saveDocument(doc);
      return outPath;
    }
    return null;
  }
}
