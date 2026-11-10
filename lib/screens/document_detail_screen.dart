import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'crop_screen.dart';
import 'camera_scan_screen.dart';
import 'ocr_screen.dart';
import '../widgets/signature_pad.dart';

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
  bool _isGridView = true; // CamScanner standard default: 2-column Grid

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

  Future<void> _deletePage(int index) async {
    if (_document == null) return;
    if (_document!.pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat menghapus satu-satunya halaman')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Hapus Halaman?'),
        content: Text('Hapus Halaman ${index + 1} dari dokumen ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ArchTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

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
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Ubah Nama Dokumen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nama Dokumen',
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
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

    PdfPaperSize selectedPaper = ThemeService.instance.defaultPaperSize;
    PdfQuality selectedQuality = ThemeService.instance.defaultQuality;
    final watermarkCtrl = TextEditingController();

    final config = await showModalBottomSheet<PdfSettings>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
              Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Pengaturan Ekspor PDF',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Ukuran Kertas',
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
                      selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      side: BorderSide(
                        color: isSel ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                      ),
                      onSelected: (_) => setModalState(() => selectedPaper = p),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Kualitas Kompresi',
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
                      selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      side: BorderSide(
                        color: isSel ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                      ),
                      onSelected: (_) =>
                          setModalState(() => selectedQuality = q),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Watermark (Opsional)',
                style: TextStyle(
                    color: ArchTheme.textSecondary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: watermarkCtrl,
                decoration: const InputDecoration(
                  hintText: 'Contoh: SALINAN / CONFIDENTIAL',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    ctx,
                    PdfSettings(
                      paperSize: selectedPaper,
                      quality: selectedQuality,
                      watermark: watermarkCtrl.text.trim().isNotEmpty
                          ? watermarkCtrl.text.trim()
                          : null,
                    ),
                  ),
                  icon: const Icon(Icons.download_done),
                  label: const Text('Buat Berkas PDF'),
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
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.picture_as_pdf, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('PDF Berhasil Dibuat'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Format: ${config.paperSize.name.toUpperCase()} (${config.quality.name.toUpperCase()}):'),
              const SizedBox(height: 8),
              SelectableText(
                pdfPath,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
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
              icon: Icon(Icons.share, color: Theme.of(context).colorScheme.primary),
              label: const Text('Bagikan'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat berkas PDF')),
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(pdfPath)],
          text: 'Dokumen: ${_document!.title} (Dipindai dengan ArchScan)',
        ),
      );
    }
  }

  Future<void> _exportLongImage() async {
    if (_document == null || _document!.pages.isEmpty) return;

    final imgPath = await DocumentStorageService.instance
        .stitchDocumentToLongImage(_document!);
    if (imgPath != null && mounted) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(imgPath)],
          text: '${_document!.title} (Gambar Panjang)',
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat gambar panjang')),
      );
    }
  }

  Future<void> _signPage(ScanPage page) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SignaturePadModal(
        onSignatureSaved: (sigPath) async {
          final outPath = page.processedImagePath;
          final success = ArchScanBridge.instance.compositeOverlay(
            basePath: page.processedImagePath,
            overlayPath: sigPath,
            outputPath: outPath,
            normX: 0.55,
            normY: 0.70,
            scale: 0.9,
          );
          if (success && mounted) {
            _document!.updatedAt = DateTime.now();
            await DocumentStorageService.instance.saveDocument(_document!);
            if (mounted) {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tanda tangan berhasil dibubuhkan pada halaman')),
              );
            }
          }
        },
      ),
    );
  }

  void _extractPageOcr(ScanPage page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrScreen(initialImagePath: page.processedImagePath),
      ),
    );
  }

  Future<void> _exportAllPagesAsImages() async {
    if (_document == null || _document!.pages.isEmpty) return;
    final files =
        _document!.pages.map((p) => XFile(p.processedImagePath)).toList();
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        text: 'Halaman Dokumen: ${_document!.title}',
      ),
    );
  }

  void _extractText() {
    if (_document == null) return;
    final allText = _document!.pages
        .expand((p) => p.ocrItems)
        .map((o) => o.text)
        .join(' ');

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                const Text('Lapisan Teks OCR',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text: allText.isNotEmpty ? allText : _document!.title));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Teks disalin ke papan klip')));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              allText.isNotEmpty
                  ? allText
                  : 'Lapisan teks dokumen diindeks otomatis untuk Searchable PDF.',
              style: const TextStyle(
                  color: ArchTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showPageActionSheet(ScanPage page, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
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
              Text(
                'Halaman ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.crop_outlined),
                title: const Text('Potong & Atur Batas (Crop)'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CropScreen(
                        imagePath: page.rawImagePath,
                        documentId: _document!.id,
                        pageId: page.id,
                      ),
                    ),
                  ).then((_) => _loadDocument());
                },
              ),
              ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: const Text('Bubuhkan Tanda Tangan'),
                onTap: () {
                  Navigator.pop(ctx);
                  _signPage(page);
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('Ekstrak Teks (OCR)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _extractPageOcr(page);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: ArchTheme.danger),
                title: const Text('Hapus Halaman Ini', style: TextStyle(color: ArchTheme.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePage(index);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    if (_document == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dokumen Tidak Ditemukan')),
        body: const Center(child: Text('Dokumen ini telah dihapus')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _renameDocument,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _document!.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 14, color: ArchTheme.textSecondary),
            ],
          ),
        ),
        actions: [
          // Toggle View (Grid 2 Kolom vs List)
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list_outlined : Icons.grid_view_outlined, size: 22),
            tooltip: _isGridView ? 'Mode Daftar' : 'Mode Kotak (Grid)',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          // Share
          IconButton(
            onPressed: _isGeneratingPdf ? null : _shareDocument,
            icon: const Icon(Icons.share_outlined, size: 22),
            tooltip: 'Bagikan',
          ),
          // More Tools Menu (Bersih & Rapi)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 22),
            onSelected: (val) {
              if (val == 'pdf') {
                _exportPdf();
              } else if (val == 'long_img') {
                _exportLongImage();
              } else if (val == 'ocr') {
                _extractText();
              } else if (val == 'images') {
                _exportAllPagesAsImages();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Ekspor Berkas PDF'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'long_img',
                child: Row(
                  children: [
                    Icon(Icons.view_agenda_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Jadikan Gambar Panjang'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ocr',
                child: Row(
                  children: [
                    Icon(Icons.text_fields_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Lapisan Teks OCR'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'images',
                child: Row(
                  children: [
                    Icon(Icons.photo_library_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Bagikan Gambar Halaman'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isGridView ? _buildGridView() : _buildListView(),
      // Bottom Action Bar persis CamScanner
      bottomNavigationBar: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor, width: 0.8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildBottomAction(
              icon: Icons.camera_alt_outlined,
              label: 'Tambah',
              color: theme.colorScheme.primary,
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CameraScanScreen(documentId: _document!.id),
                  ),
                );
                _loadDocument();
              },
            ),
            _buildBottomAction(
              icon: Icons.picture_as_pdf,
              label: 'PDF',
              color: const Color(0xFFEF4444),
              onTap: _exportPdf,
            ),
            _buildBottomAction(
              icon: Icons.share,
              label: 'Bagikan',
              color: const Color(0xFF3B82F6),
              onTap: _shareDocument,
            ),
            _buildBottomAction(
              icon: Icons.sort,
              label: 'Urutan',
              color: const Color(0xFF10B981),
              onTap: () {
                setState(() => _isGridView = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tahan dan geser item untuk mengubah urutan halaman'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // Grid 2 Kolom Khas CamScanner (Thumbnail Besar & Bersih)
  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      itemCount: _document!.pages.length,
      itemBuilder: (context, index) {
        final page = _document!.pages[index];
        return GestureDetector(
          onTap: () => _showPageActionSheet(page, index),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(page.processedImagePath),
                          fit: BoxFit.cover,
                        ),
                        // Badge Nomor Halaman di Pojok Atas
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer Informasi Halaman Rapi
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        page.filter.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: ArchTheme.textSecondary,
                        ),
                      ),
                      const Icon(Icons.more_horiz, size: 16, color: ArchTheme.textSecondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // List View dengan Drag & Drop Reorder
  Widget _buildListView() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _document!.pages.length,
      onReorderItem: (oldIndex, newIndex) async {
        setState(() {
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(page.processedImagePath),
                width: 48,
                height: 68,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(
              'Halaman ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              '${page.filter.label} • ${page.rotationDegrees}°',
              style: const TextStyle(color: ArchTheme.textSecondary, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Kelola Halaman',
                  onPressed: () => _showPageActionSheet(page, index),
                ),
                const Icon(Icons.drag_handle, color: ArchTheme.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }
}
