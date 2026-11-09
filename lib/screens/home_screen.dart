import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import '../widgets/signature_pad.dart';
import 'camera_scan_screen.dart';
import 'crop_screen.dart';
import 'document_detail_screen.dart';
import 'id_card_scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  List<ScanDocument> _documents = [];
  bool _isLoading = true;
  bool _isGridView = false;
  String _searchQuery = '';
  final Set<String> _selectedDocIds = {};
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

  Future<void> _importImages() async {
    final pickedList = await _picker.pickMultiImage();
    if (pickedList.isEmpty || !mounted) return;

    final firstPath = pickedList.first.path;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CropScreen(imagePath: firstPath)),
    );
    _refresh();
  }

  Future<void> _openSignaturePad() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SignaturePadModal(),
    );
  }

  Future<void> _batchDeleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ArchTheme.surface,
        title: const Text('Delete Selected'),
        content: Text('Delete ${_selectedDocIds.length} document(s)?'),
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
      for (final id in _selectedDocIds) {
        await DocumentStorageService.instance.deleteDocument(id);
      }
      setState(() => _selectedDocIds.clear());
      _refresh();
    }
  }

  Future<void> _batchMergePdf() async {
    if (_selectedDocIds.isEmpty) return;

    final selectedDocs =
        _documents.where((d) => _selectedDocIds.contains(d.id)).toList();
    final allPages = <ScanPage>[];
    for (final doc in selectedDocs) {
      allPages.addAll(doc.pages);
    }

    if (allPages.isEmpty) return;

    final appDir = await DocumentStorageService.instance.appDirectory;
    final pdfDir = Directory('${appDir.path}/pdfs');
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);

    final mergedId = const Uuid().v4();
    final outPath = '${pdfDir.path}/merged_$mergedId.pdf';
    final pageSpecs = allPages
        .map((p) => PageSpecData(
              imagePath: p.processedImagePath,
              ocrItems: p.ocrItems,
            ))
        .toList();

    final success = ArchScanBridge.instance.generateSearchablePdf(
      pages: pageSpecs,
      outputPdfPath: outPath,
    );

    if (success && mounted) {
      final now = DateTime.now();
      final mergedDoc = ScanDocument(
        id: mergedId,
        title: 'Merged (${selectedDocs.length} Docs) ${DateFormat('MMM dd').format(now)}',
        createdAt: now,
        updatedAt: now,
        pages: allPages,
        pdfPath: outPath,
      );
      await DocumentStorageService.instance.saveDocument(mergedDoc);
      setState(() => _selectedDocIds.clear());
      _refresh();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merged PDF created: ${mergedDoc.title}')),
      );
    }
  }

  Future<void> _batchShareSelected() async {
    final pdfFiles = <XFile>[];
    for (final id in _selectedDocIds) {
      final doc = _documents.firstWhere((d) => d.id == id);
      String? p = doc.pdfPath;
      if (p == null || !File(p).existsSync()) {
        p = await DocumentStorageService.instance.generatePdfForDocument(doc);
      }
      if (p != null) pdfFiles.add(XFile(p));
    }

    if (pdfFiles.isNotEmpty) {
      await Share.shareXFiles(pdfFiles, text: 'Documents exported via ArchScan');
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: _buildCurrentTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CameraScanScreen()),
          );
          _refresh();
        },
        child: const Icon(Icons.camera_alt),
      ),
      bottomNavigationBar: _selectedDocIds.isNotEmpty
          ? _buildBatchActionBar()
          : NavigationBar(
              selectedIndex: _currentTabIndex,
              backgroundColor: ArchTheme.surface,
              indicatorColor: ArchTheme.surfaceMuted,
              onDestinationSelected: (idx) {
                setState(() => _currentTabIndex = idx);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Beranda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Dokumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Alat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Pengaturan',
                ),
              ],
            ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTabIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildDocumentsTab();
      case 2:
        return _buildToolsTab();
      case 3:
        return _buildSettingsTab();
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    final filtered = _documents.where((d) {
      if (_searchQuery.isEmpty) return true;
      return d.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return RefreshIndicator(
      color: ArchTheme.textPrimary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          // 1. Search Bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Cari dokumen...',
              hintStyle: const TextStyle(color: ArchTheme.textSecondary, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: ArchTheme.textSecondary, size: 20),
              filled: true,
              fillColor: ArchTheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: ArchTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: ArchTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 16),

          // 2. CamScanner Quick Actions Grid (2x4)
          _buildQuickActionsGrid(),
          const SizedBox(height: 20),

          // 3. Section Header: "Terkini"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Terkini',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                '${filtered.length} Dokumen',
                style: const TextStyle(color: ArchTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 4. Documents List or Empty State
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          else if (filtered.isEmpty)
            _buildEmptyState()
          else if (_isGridView)
            _buildGridView(filtered)
          else
            _buildListView(filtered),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    final actions = [
      _QuickAction(
        icon: Icons.camera_alt_outlined,
        label: 'Scan',
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CameraScanScreen()),
          );
          _refresh();
        },
      ),
      _QuickAction(
        icon: Icons.picture_as_pdf_outlined,
        label: 'Alat PDF',
        onTap: () => setState(() => _currentTabIndex = 2),
      ),
      _QuickAction(
        icon: Icons.photo_library_outlined,
        label: 'Impor Foto',
        onTap: _importImages,
      ),
      _QuickAction(
        icon: Icons.folder_open_outlined,
        label: 'Impor File',
        onTap: _importImages,
      ),
      _QuickAction(
        icon: Icons.credit_card_outlined,
        label: 'Kartu ID',
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IdCardScanScreen()),
          );
          _refresh();
        },
      ),
      _QuickAction(
        icon: Icons.edit_outlined,
        label: 'Tanda Tangan',
        onTap: _openSignaturePad,
      ),
      _QuickAction(
        icon: Icons.qr_code_scanner_outlined,
        label: 'Scan QR',
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('QR Scanner ready')),
          );
        },
      ),
      _QuickAction(
        icon: Icons.grid_view_outlined,
        label: 'Semua',
        onTap: () => setState(() => _currentTabIndex = 2),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: ArchTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArchTheme.border, width: 1),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1.05,
          crossAxisSpacing: 4,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, i) {
          final a = actions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: a.onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(a.icon, size: 24, color: ArchTheme.textPrimary),
                const SizedBox(height: 6),
                Text(
                  a.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ArchTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildListView(List<ScanDocument> filtered) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final isSelected = _selectedDocIds.contains(doc.id);
        final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(doc.updatedAt);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              if (_selectedDocIds.isNotEmpty) {
                setState(() {
                  if (isSelected) {
                    _selectedDocIds.remove(doc.id);
                  } else {
                    _selectedDocIds.add(doc.id);
                  }
                });
              } else {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DocumentDetailScreen(documentId: doc.id),
                  ),
                );
                _refresh();
              }
            },
            onLongPress: () {
              setState(() {
                if (isSelected) {
                  _selectedDocIds.remove(doc.id);
                } else {
                  _selectedDocIds.add(doc.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: doc.thumbnailPath.isNotEmpty
                        ? Image.file(
                            File(doc.thumbnailPath),
                            width: 48,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 64,
                            color: ArchTheme.surfaceMuted,
                            child: const Icon(Icons.description, size: 20),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ArchTheme.surfaceMuted,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${doc.pageCount} p.',
                                style: const TextStyle(
                                  color: ArchTheme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: ArchTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: isSelected,
                    activeColor: Colors.white,
                    checkColor: Colors.black,
                    side: const BorderSide(color: ArchTheme.border, width: 1.5),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedDocIds.add(doc.id);
                        } else {
                          _selectedDocIds.remove(doc.id);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridView(List<ScanDocument> filtered) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final doc = filtered[index];
        final isSelected = _selectedDocIds.contains(doc.id);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              if (_selectedDocIds.isNotEmpty) {
                setState(() {
                  if (isSelected) {
                    _selectedDocIds.remove(doc.id);
                  } else {
                    _selectedDocIds.add(doc.id);
                  }
                });
              } else {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DocumentDetailScreen(documentId: doc.id),
                  ),
                );
                _refresh();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        color: ArchTheme.surfaceMuted,
                        child: doc.thumbnailPath.isNotEmpty
                            ? Image.file(File(doc.thumbnailPath), fit: BoxFit.cover)
                            : const Icon(Icons.description, color: ArchTheme.textSecondary),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${doc.pageCount} p.',
                            style: const TextStyle(color: ArchTheme.textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Checkbox(
                    value: isSelected,
                    activeColor: Colors.white,
                    checkColor: Colors.black,
                    side: const BorderSide(color: Colors.white70, width: 1.5),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedDocIds.add(doc.id);
                        } else {
                          _selectedDocIds.remove(doc.id);
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBatchActionBar() {
    return Container(
      color: ArchTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_selectedDocIds.length} dipilih',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _batchShareSelected,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Bagikan'),
                ),
                TextButton.icon(
                  onPressed: _batchMergePdf,
                  icon: const Icon(Icons.merge, size: 18),
                  label: const Text('Gabung PDF'),
                ),
                IconButton(
                  onPressed: _batchDeleteSelected,
                  icon: const Icon(Icons.delete_outline, color: ArchTheme.danger),
                  tooltip: 'Hapus',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40.0),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.document_scanner_outlined, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text(
              'Belum ada dokumen',
              style: TextStyle(color: ArchTheme.textSecondary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Semua Dokumen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.folder, color: Colors.white),
            title: const Text('Folder Default'),
            subtitle: Text('${_documents.length} dokumen'),
          ),
          const Divider(),
          ..._documents.map(
            (d) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(d.title),
              subtitle: Text('${d.pageCount} halaman'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: d.id)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsTab() {
    final tools = [
      {'icon': Icons.picture_as_pdf, 'title': 'Gabung Dokumen PDF', 'desc': 'Kombinasikan beberapa scan jadi satu file PDF'},
      {'icon': Icons.credit_card, 'title': 'Scan Kartu ID 2 Sisi', 'desc': 'Gabung depan dan belakang ke satu lembar A4'},
      {'icon': Icons.draw, 'title': 'Tanda Tangan Digital', 'desc': 'Buat tanda tangan kanvas dan terapkan ke dokumen'},
      {'icon': Icons.compress, 'title': 'Kompresi Ukuran Dokumen', 'desc': 'Perkecil ukuran berkas PDF untuk email'},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Pusat Alat Dokumen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...tools.map(
          (t) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(t['icon'] as IconData, color: Colors.white),
              title: Text(t['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t['desc'] as String, style: const TextStyle(fontSize: 12, color: ArchTheme.textSecondary)),
              onTap: () {
                if (t['title'] == 'Scan Kartu ID 2 Sisi') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const IdCardScanScreen()));
                } else if (t['title'] == 'Tanda Tangan Digital') {
                  _openSignaturePad();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pilih dokumen dari Beranda untuk ${t['title']}')),
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    final v = ArchScanBridge.instance.getVersion();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Pengaturan & Sistem', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Rust Core Engine'),
          subtitle: Text('Versi ${(v / 100).toStringAsFixed(1)} (ARM64 / x86_64 FFI Bridge)'),
          trailing: const Icon(Icons.check_circle, color: ArchTheme.accent, size: 20),
        ),
        const Divider(),
        ListTile(
          title: const Text('Penyimpanan Data'),
          subtitle: Text('${_documents.length} dokumen tersimpan di direktori lokal'),
        ),
        const Divider(),
        ListTile(
          title: const Text('Format Ekspor Default'),
          subtitle: const Text('PDF Standar ISO 32000-1 (A4 / Searchable)'),
        ),
      ],
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
