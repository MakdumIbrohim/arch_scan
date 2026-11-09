import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'crop_screen.dart';
import 'camera_scan_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  ScanDocument? _document;
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    final docs = await DocumentStorageService.instance.loadDocuments();
    final doc = docs.where((d) => d.id == widget.documentId).firstOrNull;
    if (mounted) {
      setState(() {
        _document = doc;
        _isLoading = false;
      });
    }
  }

  Future<void> _addPage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null || !mounted || _document == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          imagePath: picked.path,
          documentId: _document!.id,
        ),
      ),
    );
  }

  Future<void> _deletePage(int index) async {
    if (_document == null) return;
    if (_document!.pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the only page in the document')),
      );
      return;
    }

    setState(() {
      _document!.pages.removeAt(index);
      _document!.updatedAt = DateTime.now();
    });
    await DocumentStorageService.instance.saveDocument(_document!);
  }

  Future<void> _renameDocument() async {
    if (_document == null) return;
    final controller = TextEditingController(text: _document!.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArchTheme.surface,
        title: const Text('Rename Document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter document title',
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: ArchTheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      setState(() {
        _document!.title = newTitle;
        _document!.updatedAt = DateTime.now();
      });
      await DocumentStorageService.instance.saveDocument(_document!);
    }
  }

  Future<void> _exportPdf() async {
    if (_document == null || _document!.pages.isEmpty) return;

    PdfPaperSize selectedPaper = PdfPaperSize.a4;
    PdfQuality selectedQuality = PdfQuality.high;

    final config = await showModalBottomSheet<PdfSettings>(
      context: context,
      backgroundColor: ArchTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: ArchTheme.primary),
                  SizedBox(width: 8),
                  Text(
                    'PDF Export Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Paper Size',
                style: TextStyle(
                    color: ArchTheme.textSecondary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                children: PdfPaperSize.values.map((p) {
                  final isSel = selectedPaper == p;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(p.name.toUpperCase()),
                      selected: isSel,
                      selectedColor: ArchTheme.primary.withOpacity(0.2),
                      side: BorderSide(
                        color: isSel ? ArchTheme.primary : ArchTheme.border,
                      ),
                      onSelected: (_) => setModalState(() => selectedPaper = p),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Compression Quality',
                style: TextStyle(
                    color: ArchTheme.textSecondary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                children: PdfQuality.values.map((q) {
                  final isSel = selectedQuality == q;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(q.name.toUpperCase()),
                      selected: isSel,
                      selectedColor: ArchTheme.accent.withOpacity(0.2),
                      side: BorderSide(
                        color: isSel ? ArchTheme.accent : ArchTheme.border,
                      ),
                      onSelected: (_) =>
                          setModalState(() => selectedQuality = q),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    ctx,
                    PdfSettings(
                      paperSize: selectedPaper,
                      quality: selectedQuality,
                    ),
                  ),
                  icon: const Icon(Icons.download_done),
                  label: const Text('Generate PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (config == null || !mounted) return;

    setState(() => _isGeneratingPdf = true);
    final pdfPath = await DocumentStorageService.instance
        .generatePdfForDocument(_document!, settings: config);
    setState(() => _isGeneratingPdf = false);

    if (!mounted) return;

    if (pdfPath != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ArchTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf, color: ArchTheme.accent),
              SizedBox(width: 8),
              Text('PDF Generated'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Created with ${config.paperSize.name.toUpperCase()} format (${config.quality.name.toUpperCase()} quality):'),
              const SizedBox(height: 8),
              SelectableText(
                pdfPath,
                style: const TextStyle(
                  color: ArchTheme.primary,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _shareDocument();
              },
              icon: const Icon(Icons.share, color: ArchTheme.accent),
              label: const Text('Share'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to generate PDF')),
      );
    }
  }

  Future<void> _shareDocument() async {
    if (_document == null || _document!.pages.isEmpty) return;

    String? pdfPath = _document!.pdfPath;
    if (pdfPath == null || !File(pdfPath).existsSync()) {
      setState(() => _isGeneratingPdf = true);
      pdfPath = await DocumentStorageService.instance.generatePdfForDocument(_document!);
      setState(() => _isGeneratingPdf = false);
    }

    if (pdfPath != null && mounted) {
      await Share.shareXFiles(
        [XFile(pdfPath)],
        text: 'Document: ${_document!.title} (Scanned with ArchScan)',
      );
    }
  }

  Future<void> _exportLongImage() async {
    if (_document == null || _document!.pages.isEmpty) return;

    final imgPath = await DocumentStorageService.instance
        .stitchDocumentToLongImage(_document!);
    if (imgPath != null && mounted) {
      await Share.shareXFiles(
        [XFile(imgPath)],
        text: '${_document!.title} (Stitched Long Image)',
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to stitch long image')),
      );
    }
  }

  void _extractText() {
    if (_document == null) return;
    final allText = _document!.pages
        .expand((p) => p.ocrItems)
        .map((o) => o.text)
        .join(' ');

    showModalBottomSheet(
      context: context,
      backgroundColor: ArchTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('OCR Text Layer',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: allText.isNotEmpty ? allText : _document!.title));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              allText.isNotEmpty
                  ? allText
                  : 'Document text layer indexed for Searchable PDF.',
              style: const TextStyle(
                  color: ArchTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: ArchTheme.primary)),
      );
    }

    if (_document == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document Not Found')),
        body: const Center(child: Text('Document was deleted')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _renameDocument,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  _document!.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit, size: 16, color: ArchTheme.textSecondary),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _extractText,
            icon: const Icon(Icons.text_fields_outlined, size: 20),
            tooltip: 'OCR Text Layer',
          ),
          IconButton(
            onPressed: _exportLongImage,
            icon: const Icon(Icons.view_agenda_outlined, size: 20),
            tooltip: 'Stitch Long Image',
          ),
          IconButton(
            onPressed: _isGeneratingPdf ? null : _shareDocument,
            icon: const Icon(Icons.share, size: 20),
            tooltip: 'Share Document',
          ),
          IconButton(
            onPressed: _isGeneratingPdf ? null : _exportPdf,
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ArchTheme.primary),
                  )
                : const Icon(Icons.picture_as_pdf, color: ArchTheme.primary),
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _document!.pages.length,
        onReorder: (oldIndex, newIndex) async {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final page = _document!.pages.removeAt(oldIndex);
            _document!.pages.insert(newIndex, page);
            _document!.updatedAt = DateTime.now();
          });
          await DocumentStorageService.instance.saveDocument(_document!);
        },
        itemBuilder: (context, index) {
          final page = _document!.pages[index];
          return Card(
            key: ValueKey(page.id),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(page.processedImagePath),
                  width: 50,
                  height: 70,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(
                'Page ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Filter: ${page.filter.label} • Rotation: ${page.rotationDegrees}°',
                style: const TextStyle(color: ArchTheme.textSecondary, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.crop, color: ArchTheme.primary),
                    tooltip: 'Re-crop',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CropScreen(
                            imagePath: page.rawImagePath,
                            documentId: _document!.id,
                            pageId: page.id,
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: ArchTheme.danger),
                    tooltip: 'Delete Page',
                    onPressed: () => _deletePage(index),
                  ),
                  const Icon(Icons.drag_handle, color: ArchTheme.textSecondary),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_document == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CameraScanScreen(documentId: _document!.id),
            ),
          );
          _loadDocument();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Page'),
      ),
    );
  }
}
