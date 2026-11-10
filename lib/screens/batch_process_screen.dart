import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'document_detail_screen.dart';

class BatchProcessScreen extends StatefulWidget {
  final List<String> imagePaths;
  final String? documentId;

  const BatchProcessScreen({
    super.key,
    required this.imagePaths,
    this.documentId,
  });

  @override
  State<BatchProcessScreen> createState() => _BatchProcessScreenState();
}

class _BatchProcessScreenState extends State<BatchProcessScreen> {
  int _currentIndex = 0;
  int _total = 0;
  String _statusText = 'Initializing batch processor...';

  @override
  void initState() {
    super.initState();
    _total = widget.imagePaths.length;
    _runBatchProcessing();
  }

  Future<void> _runBatchProcessing() async {
    final appDir = await DocumentStorageService.instance.appDirectory;
    final pagesDir = Directory('${appDir.path}/pages');
    if (!await pagesDir.exists()) await pagesDir.create(recursive: true);

    final generatedPages = <ScanPage>[];

    for (int i = 0; i < widget.imagePaths.length; i++) {
      if (!mounted) return;
      setState(() {
        _currentIndex = i + 1;
        _statusText = 'Processing page $_currentIndex of $_total...';
      });

      final rawPath = widget.imagePaths[i];
      final pageId = const Uuid().v4();
      final outPath = '${pagesDir.path}/page_$pageId.jpg';

      // 1. Detect corners via Rust
      final corners = ArchScanBridge.instance.detectCorners(rawPath);

      final defaultFilter = ThemeService.instance.defaultFilter;

      // 2. Warp & apply configured filter via Rust
      final success = ArchScanBridge.instance.processPage(
        inputPath: rawPath,
        outputPath: outPath,
        corners: corners,
        filter: defaultFilter,
        rotationDegrees: 0,
      );

      final finalPath = success ? outPath : rawPath;

      generatedPages.add(
        ScanPage(
          id: pageId,
          rawImagePath: rawPath,
          processedImagePath: finalPath,
          corners: corners,
          filter: defaultFilter,
          rotationDegrees: 0,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _statusText = 'Saving document...');

    ScanDocument targetDoc;
    if (widget.documentId != null) {
      final docs = await DocumentStorageService.instance.loadDocuments();
      final idx = docs.indexWhere((d) => d.id == widget.documentId);
      if (idx >= 0) {
        targetDoc = docs[idx];
        targetDoc.pages.addAll(generatedPages);
        targetDoc.updatedAt = DateTime.now();
      } else {
        final now = DateTime.now();
        targetDoc = ScanDocument(
          id: const Uuid().v4(),
          title:
              'Batch Scan ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          createdAt: now,
          updatedAt: now,
          pages: generatedPages,
        );
      }
    } else {
      final now = DateTime.now();
      targetDoc = ScanDocument(
        id: const Uuid().v4(),
        title: 'Batch Scan ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        createdAt: now,
        updatedAt: now,
        pages: generatedPages,
      );
    }

    await DocumentStorageService.instance.saveDocument(targetDoc);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DocumentDetailScreen(documentId: targetDoc.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_currentIndex / _total).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: ArchTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.auto_fix_high,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ArchTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: ArchTheme.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toInt()}% completed',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ArchTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
