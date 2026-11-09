import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'crop_screen.dart';
import 'document_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScanDocument> _documents = [];
  bool _isLoading = true;
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

    final rustVersion = ArchScanBridge.instance.getVersion();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ArchTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ArchTheme.primary, width: 1),
              ),
              child: const Text(
                'ARCH',
                style: TextStyle(
                  color: ArchTheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('ArchScan'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                'Rust v${(rustVersion / 100).toStringAsFixed(1)}',
                style: const TextStyle(
                  color: ArchTheme.accent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
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
                        color: ArchTheme.primary,
                        onRefresh: _refresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            final dateStr = DateFormat('MMM dd, yyyy • HH:mm')
                                .format(doc.updatedAt);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DocumentDetailScreen(
                                        documentId: doc.id,
                                      ),
                                    ),
                                  );
                                  _refresh();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      // Thumbnail
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: doc.thumbnailPath.isNotEmpty
                                            ? Image.file(
                                                File(doc.thumbnailPath),
                                                width: 60,
                                                height: 80,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 60,
                                                height: 80,
                                                color: ArchTheme.surfaceLight,
                                                child: const Icon(Icons.image),
                                              ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              doc.title,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${doc.pageCount} ${doc.pageCount == 1 ? 'page' : 'pages'}',
                                              style: const TextStyle(
                                                color: ArchTheme.primary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              dateStr,
                                              style: const TextStyle(
                                                color: ArchTheme.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Menu options
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert,
                                            color: ArchTheme.textSecondary),
                                        color: ArchTheme.surface,
                                        onSelected: (val) {
                                          if (val == 'delete') {
                                            _deleteDocument(doc);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline,
                                                    color: ArchTheme.danger,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text('Delete',
                                                    style: TextStyle(
                                                        color: ArchTheme.danger)),
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
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: ArchTheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: ArchTheme.primary),
                    title: const Text('Scan with Camera'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _startScan(ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: ArchTheme.accent),
                    title: const Text('Import from Gallery'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _startScan(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ),
          );
        },
        icon: const Icon(Icons.camera_alt),
        label: const Text('Scan Document'),
      ),
    );
  }
}
