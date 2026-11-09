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
import 'batch_process_screen.dart';

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
  String _selectedCategory = 'Semua';
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

    if (pickedList.length > 1) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BatchProcessScreen(
            imagePaths: pickedList.map((e) => e.path).toList(),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CropScreen(imagePath: pickedList.first.path),
        ),
      );
    }
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
        backgroundColor: Theme.of(context).colorScheme.surface,
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
      if (!mounted) return;
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
      await SharePlus.instance.share(
        ShareParams(
          files: pdfFiles,
          text: 'Documents exported via ArchScan',
        ),
      );
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
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1F2937)
                  : const Color(0xFFE2E8F0),
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
        children: [
          // 1. Search Bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Cari dokumen...',
              hintStyle: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? ArchTheme.darkTextSecondary
                    : ArchTheme.lightTextSecondary,
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Theme.of(context).brightness == Brightness.dark
                    ? ArchTheme.darkTextSecondary
                    : ArchTheme.lightTextSecondary,
                size: 20,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
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
        color: const Color(0xFF2563EB),
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
        color: const Color(0xFFEF4444),
        onTap: () => setState(() => _currentTabIndex = 2),
      ),
      _QuickAction(
        icon: Icons.photo_library_outlined,
        label: 'Impor Foto',
        color: const Color(0xFF3B82F6),
        onTap: _importImages,
      ),
      _QuickAction(
        icon: Icons.folder_open_outlined,
        label: 'Impor File',
        color: const Color(0xFFF59E0B),
        onTap: _importImages,
      ),
      _QuickAction(
        icon: Icons.credit_card_outlined,
        label: 'Kartu ID',
        color: const Color(0xFF8B5CF6),
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
        color: const Color(0xFF10B981),
        onTap: _openSignaturePad,
      ),
      _QuickAction(
        icon: Icons.qr_code_scanner_outlined,
        label: 'Scan QR',
        color: const Color(0xFF06B6D4),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('QR Scanner ready')),
          );
        },
      ),
      _QuickAction(
        icon: Icons.grid_view_outlined,
        label: 'Semua',
        color: const Color(0xFF6366F1),
        onTap: () => setState(() => _currentTabIndex = 2),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
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
                Icon(a.icon, size: 24, color: a.color),
                const SizedBox(height: 6),
                Text(
                  a.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
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
                    activeColor: Theme.of(context).colorScheme.primary,
                    checkColor: Colors.white,
                    side: BorderSide(color: Theme.of(context).dividerColor, width: 1.5),
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
                    activeColor: Theme.of(context).colorScheme.primary,
                    checkColor: Colors.white,
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
      color: Theme.of(context).colorScheme.surface,
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
            Icon(Icons.document_scanner_outlined, size: 48, color: ArchTheme.textSecondary.withValues(alpha: 0.4)),
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
    final categories = ['Semua', 'Kartu ID', 'Bisnis', 'Pribadi'];
    final categoryDocs = _documents.where((d) {
      if (_selectedCategory == 'Kartu ID') {
        return d.title.toLowerCase().contains('id card') ||
            d.title.toLowerCase().contains('kartu');
      } else if (_selectedCategory == 'Bisnis') {
        return d.title.toLowerCase().contains('invoice') ||
            d.title.toLowerCase().contains('bisnis');
      } else if (_selectedCategory == 'Pribadi') {
        return !d.title.toLowerCase().contains('id card') &&
            !d.title.toLowerCase().contains('kartu');
      }
      return true;
    }).toList();

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Semua Dokumen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${categoryDocs.length} Dokumen',
                  style: const TextStyle(
                      color: ArchTheme.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          // Category filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSel = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSel,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSel
                          ? Colors.white
                          : (Theme.of(context).brightness == Brightness.dark
                              ? ArchTheme.darkTextPrimary
                              : ArchTheme.lightTextPrimary),
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (categoryDocs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Center(
                child: Text('Tidak ada dokumen di kategori $_selectedCategory',
                    style: const TextStyle(color: ArchTheme.textSecondary)),
              ),
            )
          else
            ...categoryDocs.map(
              (d) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: d.thumbnailPath.isNotEmpty
                        ? Image.file(
                            File(d.thumbnailPath),
                            width: 44,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 44,
                            height: 56,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? ArchTheme.darkSurfaceMuted
                                : ArchTheme.lightSurfaceMuted,
                            child: const Icon(Icons.description, size: 20),
                          ),
                  ),
                  title: Text(d.title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${d.pageCount} halaman • ${DateFormat('dd/MM/yyyy').format(d.updatedAt)}',
                      style: const TextStyle(fontSize: 12, color: ArchTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              DocumentDetailScreen(documentId: d.id)),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolsTab() {
    final tools = [
      {
        'icon': Icons.picture_as_pdf_outlined,
        'color': const Color(0xFFEF4444),
        'title': 'Gabung Dokumen PDF',
        'desc': 'Kombinasikan beberapa dokumen pindaian jadi satu berkas PDF'
      },
      {
        'icon': Icons.view_agenda_outlined,
        'color': const Color(0xFFF59E0B),
        'title': 'Ekspor Gambar Panjang (Long Stitch)',
        'desc': 'Satukan seluruh halaman secara vertikal jadi 1 berkas gambar panjang'
      },
      {
        'icon': Icons.credit_card_outlined,
        'color': const Color(0xFF8B5CF6),
        'title': 'Scan Kartu ID 2 Sisi',
        'desc': 'Gabung tampak depan dan belakang kartu identitas ke 1 lembar A4'
      },
      {
        'icon': Icons.edit_outlined,
        'color': const Color(0xFF10B981),
        'title': 'Tanda Tangan Digital',
        'desc': 'Buat tanda tangan kanvas dan simpan untuk dokumen'
      },
      {
        'icon': Icons.branding_watermark_outlined,
        'color': const Color(0xFF0D9488),
        'title': 'Watermark Dokumen',
        'desc': 'Bubuhkan watermark teks kustom pada berkas PDF pindaian'
      },
      {
        'icon': Icons.compress_outlined,
        'color': const Color(0xFF2563EB),
        'title': 'Kompresi Ukuran Dokumen',
        'desc': 'Perkecil ukuran berkas PDF untuk keperluan kirim email/WA'
      },
      {
        'icon': Icons.qr_code_scanner_outlined,
        'color': const Color(0xFF06B6D4),
        'title': 'Scan QR & Barcode',
        'desc': 'Pindai kode QR atau barcode produk dari kamera'
      },
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor =
        isDark ? ArchTheme.darkTextSecondary : ArchTheme.lightTextSecondary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        const Text('Pusat Alat Dokumen',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...tools.map((t) {
          final iconColor = t['color'] as Color;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(t['icon'] as IconData, color: iconColor, size: 22),
              ),
              title: Text(t['title'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(t['desc'] as String,
                  style: TextStyle(fontSize: 12, color: subColor)),
              trailing: Icon(Icons.chevron_right, size: 18, color: subColor),
              onTap: () async {
                final title = t['title'] as String;
                if (title == 'Scan Kartu ID 2 Sisi') {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const IdCardScanScreen()));
                } else if (title == 'Tanda Tangan Digital') {
                  _openSignaturePad();
                } else if (title.contains('Gambar Panjang')) {
                  if (_documents.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Belum ada dokumen untuk digabung')),
                    );
                    return;
                  }
                  // Let user pick a document to stitch
                  final selected = await showDialog<ScanDocument>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Pilih Dokumen'),
                      children: _documents
                          .map((d) => SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, d),
                                child: Text('${d.title} (${d.pageCount} hal.)'),
                              ))
                          .toList(),
                    ),
                  );
                  if (selected != null) {
                    final out = await DocumentStorageService.instance
                        .stitchDocumentToLongImage(selected);
                    if (out != null) {
                      await SharePlus.instance.share(ShareParams(
                        files: [XFile(out)],
                        text: '${selected.title} (Gambar Panjang)',
                      ));
                    }
                  }
                } else if (title == 'Gabung Dokumen PDF') {
                  setState(() => _currentTabIndex = 0);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pilih dokumen yang ingin digabung menggunakan kotak ceklis di Beranda'),
                    ),
                  );
                } else if (title == 'Scan QR & Barcode') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Arahkan kamera ke kode QR / Barcode')),
                  );
                } else {
                  if (_documents.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DocumentDetailScreen(
                              documentId: _documents.first.id)),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Pindai dokumen terlebih dahulu untuk $title')),
                    );
                  }
                }
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSettingsTab() {
    final themeService = ThemeService.instance;

    final accentColors = [
      {'name': 'Blue', 'color': const Color(0xFF2563EB)},
      {'name': 'Teal', 'color': const Color(0xFF0D9488)},
      {'name': 'Cyan', 'color': const Color(0xFF0284C7)},
      {'name': 'Purple', 'color': const Color(0xFF7C3AED)},
      {'name': 'Amber', 'color': const Color(0xFFD97706)},
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        const Text(
          'Pengaturan',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Section: Tampilan & Tema
        _buildSettingsSectionHeader('TAMPILAN & TEMA'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mode Tema',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildThemeChip('Gelap', ThemeMode.dark, themeService),
                    const SizedBox(width: 8),
                    _buildThemeChip('Terang', ThemeMode.light, themeService),
                    const SizedBox(width: 8),
                    _buildThemeChip('Sistem', ThemeMode.system, themeService),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Warna Aksen',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Row(
                  children: accentColors.map((item) {
                    final color = item['color'] as Color;
                    final isSelected = themeService.accentColor == color;
                    return GestureDetector(
                      onTap: () => themeService.setAccentColor(color),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Section: Pengaturan Pindai & PDF
        _buildSettingsSectionHeader('PEMINDAIAN & DOKUMEN'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Filter Pindaian Bawaan'),
                subtitle: Text(themeService.defaultFilter.label),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: ScanFilter.values
                            .map((f) => ListTile(
                                  title: Text(f.label),
                                  trailing: themeService.defaultFilter == f
                                      ? Icon(Icons.check, color: themeService.accentColor)
                                      : null,
                                  onTap: () {
                                    themeService.setDefaultFilter(f);
                                    Navigator.pop(ctx);
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Ukuran Kertas PDF'),
                subtitle: Text(themeService.defaultPaperSize.label),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: PdfPaperSize.values
                            .map((p) => ListTile(
                                  title: Text(p.label),
                                  trailing: themeService.defaultPaperSize == p
                                      ? Icon(Icons.check, color: themeService.accentColor)
                                      : null,
                                  onTap: () {
                                    themeService.setDefaultPaperSize(p);
                                    Navigator.pop(ctx);
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Kualitas Ekspor PDF'),
                subtitle: Text(themeService.defaultQuality.label),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: PdfQuality.values
                            .map((q) => ListTile(
                                  title: Text(q.label),
                                  trailing: themeService.defaultQuality == q
                                      ? Icon(Icons.check, color: themeService.accentColor)
                                      : null,
                                  onTap: () {
                                    themeService.setDefaultQuality(q);
                                    Navigator.pop(ctx);
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Section: Penyimpanan & Cache
        _buildSettingsSectionHeader('PENYIMPANAN & CACHE'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Dokumen Tersimpan'),
                subtitle: Text('${_documents.length} dokumen'),
              ),
              const Divider(),
              ListTile(
                title: const Text('Bersihkan Cache Sementara'),
                subtitle: const Text('Hapus berkas pratinjau yang tidak terpakai'),
                trailing: const Icon(Icons.cleaning_services_outlined, size: 20),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final dir = await DocumentStorageService.instance.appDirectory;
                  final temp = Directory('${dir.path}/temp');
                  if (temp.existsSync()) {
                    temp.deleteSync(recursive: true);
                  }
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Cache sementara berhasil dibersihkan')),
                  );
                },
              ),
              if (_documents.isNotEmpty) ...[
                const Divider(),
                ListTile(
                  title: const Text(
                    'Hapus Semua Dokumen',
                    style: TextStyle(color: ArchTheme.danger),
                  ),
                  subtitle: const Text('Hapus permanen seluruh dokumen dari perangkat'),
                  trailing: const Icon(Icons.delete_forever_outlined, color: ArchTheme.danger, size: 20),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Hapus Semua Dokumen?'),
                        content: const Text('Tindakan ini tidak dapat dibatalkan.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Batal'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: ArchTheme.danger),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Hapus Semua'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      for (final d in List.from(_documents)) {
                        await DocumentStorageService.instance.deleteDocument(d.id);
                      }
                      _refresh();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Section: Tentang Aplikasi
        _buildSettingsSectionHeader('INFORMASI APLIKASI'),
        const Card(
          child: ListTile(
            title: Text('Versi Aplikasi'),
            subtitle: Text('ArchScan 1.0.0'),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSettingsSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF475569),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildThemeChip(String label, ThemeMode mode, ThemeService service) {
    final isSelected = service.themeMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedText =
        isSelected ? Colors.white : (isDark ? const Color(0xFFF9FAFB) : const Color(0xFF0F172A));
    final unselectedBorder =
        isDark ? const Color(0xFF374151) : const Color(0xFFCBD5E1);
    final unselectedBg =
        isDark ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: service.accentColor,
      backgroundColor: unselectedBg,
      labelStyle: TextStyle(
        color: unselectedText,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? service.accentColor : unselectedBorder,
      ),
      onSelected: (_) => service.setThemeMode(mode),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}
