import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'crop_screen.dart';
import 'camera_scan_screen.dart';
import 'document_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScanDocument> _documents = [];
  bool _isLoading = true;
  bool _isGridView = false;
  String _searchQuery = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final docs = await DocumentStorageService.instance.loadDocuments();
    if (mounted) {
      setState(() {
        _documents = docs;
        _isLoading = false;
      });
    }
  }

  Future<void> _startScan(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CropScreen(imagePath: picked.path),
      ),
    );
    _refresh();
  }

  Future<void> _shareDocument(ScanDocument doc) async {
    if (doc.pages.isEmpty) return;
    String? pdfPath = doc.pdfPath;
    if (pdfPath == null || !File(pdfPath).existsSync()) {
      pdfPath = await DocumentStorageService.instance.generatePdfForDocument(doc);
    }
    if (pdfPath != null) {
      await Share.shareXFiles(
        [XFile(pdfPath)],
        text: 'Document: ${doc.title} (Scanned with ArchScan)',
      );
    }
  }

  Future<void> _deleteDocument(ScanDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArchTheme.surface,
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${doc.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ArchTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DocumentStorageService.instance.deleteDocument(doc.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _documents.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ArchScan'),
        actions: [
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list_outlined : Icons.grid_view_outlined,
              size: 20,
            ),
            tooltip: _isGridView ? 'List View' : 'Grid View',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search scanned documents...',
                hintStyle: const TextStyle(color: ArchTheme.textSecondary),
                prefixIcon: const Icon(Icons.search, color: ArchTheme.textSecondary),
                filled: true,
                fillColor: ArchTheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ArchTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ArchTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: ArchTheme.primary),
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
          ),
          // Document List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: ArchTheme.primary))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.document_scanner_outlined,
                              size: 72,
                              color: ArchTheme.textSecondary.withOpacity(0.4),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No documents yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: ArchTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap the scan button below to scan your first document',
                              style: TextStyle(
                                fontSize: 13,
                                color: ArchTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: ArchTheme.textPrimary,
                        onRefresh: _refresh,
                        child: _isGridView
                            ? GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final doc = filtered[index];
                                  final dateStr =
                                      DateFormat('MMM dd').format(doc.updatedAt);
                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                DocumentDetailScreen(
                                                    documentId: doc.id),
                                          ),
                                        );
                                        _refresh();
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              width: double.infinity,
                                              color: ArchTheme.surfaceMuted,
                                              child: doc.thumbnailPath.isNotEmpty
                                                  ? Image.file(
                                                      File(doc.thumbnailPath),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(Icons.description,
                                                      color: ArchTheme
                                                          .textSecondary),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  doc.title,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      '${doc.pageCount} p.',
                                                      style: const TextStyle(
                                                        color: ArchTheme
                                                            .textSecondary,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    Text(
                                                      dateStr,
                                                      style: const TextStyle(
                                                        color: ArchTheme
                                                            .textSecondary,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final doc = filtered[index];
                                  final dateStr =
                                      DateFormat('MMM dd, yyyy • HH:mm')
                                          .format(doc.updatedAt);

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                DocumentDetailScreen(
                                                    documentId: doc.id),
                                          ),
                                        );
                                        _refresh();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(10.0),
                                        child: Row(
                                          children: [
                                            // Thumbnail
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: doc.thumbnailPath.isNotEmpty
                                                  ? Image.file(
                                                      File(doc.thumbnailPath),
                                                      width: 52,
                                                      height: 68,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Container(
                                                      width: 52,
                                                      height: 68,
                                                      color:
                                                          ArchTheme.surfaceMuted,
                                                      child: const Icon(
                                                          Icons.description),
                                                    ),
                                            ),
                                            const SizedBox(width: 14),
                                            // Info
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    doc.title,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${doc.pageCount} ${doc.pageCount == 1 ? 'page' : 'pages'} • $dateStr',
                                                    style: const TextStyle(
                                                      color: ArchTheme
                                                          .textSecondary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Menu options
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert,
                                                  color:
                                                      ArchTheme.textSecondary,
                                                  size: 18),
                                              color: ArchTheme.surface,
                                              onSelected: (val) {
                                                if (val == 'delete') {
                                                  _deleteDocument(doc);
                                                } else if (val == 'share') {
                                                  _shareDocument(doc);
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                const PopupMenuItem(
                                                  value: 'share',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.share,
                                                          color:
                                                              ArchTheme.accent,
                                                          size: 18),
                                                      SizedBox(width: 8),
                                                      Text('Share PDF',
                                                          style: TextStyle(
                                                              fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete_outline,
                                                          color:
                                                              ArchTheme.danger,
                                                          size: 18),
                                                      SizedBox(width: 8),
                                                      Text('Delete',
                                                          style: TextStyle(
                                                              color: ArchTheme
                                                                  .danger,
                                                              fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CameraScanScreen()),
          );
          _refresh();
        },
        icon: const Icon(Icons.camera_alt),
        label: const Text('Scan Document'),
      ),
    );
  }
}
