import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'document_detail_screen.dart';

class FilterScreen extends StatefulWidget {
  final String rawImagePath;
  final List<Point2D> corners;
  final String? documentId;
  final String? pageId;

  const FilterScreen({
    super.key,
    required this.rawImagePath,
    required this.corners,
    this.documentId,
    this.pageId,
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  ScanFilter _selectedFilter = ScanFilter.magicColor;
  int _rotation = 0;
  String? _previewPath;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _processPreview();
  }

  Future<void> _processPreview() async {
    setState(() => _isProcessing = true);

    final appDir = await DocumentStorageService.instance.appDirectory;
    final tempDir = Directory('${appDir.path}/temp');
    if (!await tempDir.exists()) await tempDir.create(recursive: true);

    final outPath = '${tempDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final success = ArchScanBridge.instance.processPage(
      inputPath: widget.rawImagePath,
      outputPath: outPath,
      corners: widget.corners,
      filter: _selectedFilter,
      rotationDegrees: _rotation,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        if (success) _previewPath = outPath;
      });
    }
  }

  void _onRotate() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
    });
    _processPreview();
  }

  void _onFilterSelected(ScanFilter filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
    });
    _processPreview();
  }

  Future<void> _savePage() async {
    if (_previewPath == null) return;
    setState(() => _isProcessing = true);

    final appDir = await DocumentStorageService.instance.appDirectory;
    final pagesDir = Directory('${appDir.path}/pages');
    if (!await pagesDir.exists()) await pagesDir.create(recursive: true);

    final pageId = widget.pageId ?? const Uuid().v4();
    final finalPath = '${pagesDir.path}/page_$pageId.jpg';

    // Copy current preview to durable page storage
    await File(_previewPath!).copy(finalPath);

    final scanPage = ScanPage(
      id: pageId,
      rawImagePath: widget.rawImagePath,
      processedImagePath: finalPath,
      corners: widget.corners,
      filter: _selectedFilter,
      rotationDegrees: _rotation,
    );

    ScanDocument targetDoc;
    if (widget.documentId != null) {
      final docs = await DocumentStorageService.instance.loadDocuments();
      targetDoc = docs.firstWhere((d) => d.id == widget.documentId);
      final pIdx = targetDoc.pages.indexWhere((p) => p.id == pageId);
      if (pIdx >= 0) {
        targetDoc.pages[pIdx] = scanPage;
      } else {
        targetDoc.pages.add(scanPage);
      }
      targetDoc.updatedAt = DateTime.now();
    } else {
      final docId = const Uuid().v4();
      final now = DateTime.now();
      targetDoc = ScanDocument(
        id: docId,
        title: 'Document ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        createdAt: now,
        updatedAt: now,
        pages: [scanPage],
      );
    }

    await DocumentStorageService.instance.saveDocument(targetDoc);

    if (mounted) {
      // Navigate to detail screen or pop
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DocumentDetailScreen(documentId: targetDoc.id),
        ),
        (route) => route.isFirst,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Enhance & Filter'),
        actions: [
          IconButton(
            onPressed: _onRotate,
            icon: const Icon(Icons.rotate_right, color: ArchTheme.primary),
            tooltip: 'Rotate 90°',
          ),
          IconButton(
            onPressed: _savePage,
            icon: const Icon(Icons.check, color: ArchTheme.accent),
            tooltip: 'Save',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _isProcessing && _previewPath == null
                  ? const CircularProgressIndicator(color: ArchTheme.primary)
                  : _previewPath != null
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_previewPath!),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            if (_isProcessing)
                              Container(
                                color: Colors.black45,
                                child: const CircularProgressIndicator(
                                    color: ArchTheme.primary),
                              ),
                          ],
                        )
                      : const Text(
                          'Processing failed',
                          style: TextStyle(color: ArchTheme.danger),
                        ),
            ),
          ),
          // Filter options bar
          Container(
            color: ArchTheme.surface,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: ScanFilter.values.map((f) {
                  final isSelected = (_selectedFilter == f);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: isSelected,
                      selectedColor: ArchTheme.primary.withOpacity(0.2),
                      backgroundColor: ArchTheme.surfaceLight,
                      labelStyle: TextStyle(
                        color: isSelected ? ArchTheme.primary : ArchTheme.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected ? ArchTheme.primary : Colors.transparent,
                        width: 1.5,
                      ),
                      onSelected: (_) => _onFilterSelected(f),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
