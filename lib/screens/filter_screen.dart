import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'crop_screen.dart';
import 'document_detail_screen.dart';
import 'erase_screen.dart';

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
  late List<Point2D> _currentCorners;

  @override
  void initState() {
    super.initState();
    _currentCorners = List.from(widget.corners);
    _selectedFilter = ThemeService.instance.defaultFilter;
    _processPreview();
  }

  Future<void> _processPreview() async {
    setState(() => _isProcessing = true);

    final appDir = await DocumentStorageService.instance.appDirectory;
    final tempDir = Directory('${appDir.path}/temp');
    if (!await tempDir.exists()) await tempDir.create(recursive: true);

    final outPath =
        '${tempDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final success = ArchScanBridge.instance.processPage(
      inputPath: widget.rawImagePath,
      outputPath: outPath,
      corners: _currentCorners,
      filter: _selectedFilter,
      rotationDegrees: _rotation,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        if (success) {
          _previewPath = outPath;
        } else {
          _previewPath ??= widget.rawImagePath;
        }
      });
    }
  }

  void _onRotate() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
    });
    _processPreview();
  }

  void _openFilterSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Pilih Filter Dokumen',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...ScanFilter.values.map((f) {
                final isSelected = (_selectedFilter == f);
                return ListTile(
                  title: Text(f.label),
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_selectedFilter != f) {
                      setState(() => _selectedFilter = f);
                      _processPreview();
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCrop() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          imagePath: widget.rawImagePath,
          documentId: widget.documentId,
          pageId: widget.pageId,
        ),
      ),
    );
    _processPreview();
  }

  Future<void> _openSmartErase() async {
    if (_previewPath == null) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EraseScreen(
          imagePath: _previewPath!,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _previewPath = result;
      });
    }
  }

  Future<void> _savePage() async {
    if (_previewPath == null) return;
    setState(() => _isProcessing = true);

    final appDir = await DocumentStorageService.instance.appDirectory;
    final pagesDir = Directory('${appDir.path}/pages');
    if (!await pagesDir.exists()) await pagesDir.create(recursive: true);

    final pageId = widget.pageId ?? const Uuid().v4();
    final finalPath = '${pagesDir.path}/page_$pageId.jpg';

    final srcFile = File(_previewPath ?? widget.rawImagePath);
    if (await srcFile.exists()) {
      await srcFile.copy(finalPath);
    }

    final scanPage = ScanPage(
      id: pageId,
      rawImagePath: widget.rawImagePath,
      processedImagePath: finalPath,
      corners: _currentCorners,
      filter: _selectedFilter,
      rotationDegrees: _rotation,
    );

    ScanDocument targetDoc;
    if (widget.documentId != null) {
      final docs = await DocumentStorageService.instance.loadDocuments();
      final dIdx = docs.indexWhere((d) => d.id == widget.documentId);
      if (dIdx >= 0) {
        targetDoc = docs[dIdx];
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
          title:
              'Document ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          createdAt: now,
          updatedAt: now,
          pages: [scanPage],
        );
      }
    } else {
      final docId = const Uuid().v4();
      final now = DateTime.now();
      targetDoc = ScanDocument(
        id: docId,
        title:
            'Document ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        createdAt: now,
        updatedAt: now,
        pages: [scanPage],
      );
    }

    await DocumentStorageService.instance.saveDocument(targetDoc);

    if (mounted) {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF1F3F4),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Hasil Pindaian',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: FilledButton.icon(
              onPressed: _savePage,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Simpan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Large Document Preview Card (Material 3 Google Scan style)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Center(
                child: _isProcessing && _previewPath == null
                    ? CircularProgressIndicator(color: theme.colorScheme.primary)
                    : Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.file(
                                File(_previewPath ?? widget.rawImagePath),
                                fit: BoxFit.contain,
                              ),
                              if (_isProcessing)
                                Container(
                                  color: Colors.black38,
                                  child: CircularProgressIndicator(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // 2. Material 3 Bottom Tool Carousel (Google Scan Style: Crop, Filter, Rotate, Erase)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildGoogleScanAction(
                    icon: Icons.crop_outlined,
                    label: 'Potong & Sudut',
                    onTap: _openCrop,
                    color: theme.colorScheme.onSurface,
                  ),
                  _buildGoogleScanAction(
                    icon: Icons.color_lens_outlined,
                    label: _selectedFilter.label,
                    onTap: _openFilterSelector,
                    color: theme.colorScheme.primary,
                  ),
                  _buildGoogleScanAction(
                    icon: Icons.rotate_right_outlined,
                    label: 'Putar (90°)',
                    onTap: _onRotate,
                    color: theme.colorScheme.onSurface,
                  ),
                  _buildGoogleScanAction(
                    icon: Icons.auto_fix_high_outlined,
                    label: 'Hapus Noda',
                    onTap: _openSmartErase,
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleScanAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
