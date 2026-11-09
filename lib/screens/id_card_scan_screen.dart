import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../models/document_model.dart';
import '../services/document_storage.dart';
import 'document_detail_screen.dart';

class IdCardScanScreen extends StatefulWidget {
  const IdCardScanScreen({super.key});

  @override
  State<IdCardScanScreen> createState() => _IdCardScanScreenState();
}

class _IdCardScanScreenState extends State<IdCardScanScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _frontPath;
  String? _backPath;
  bool _isProcessing = false;

  Future<void> _captureCard(bool isFront) async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;

    setState(() {
      if (isFront) {
        _frontPath = picked.path;
      } else {
        _backPath = picked.path;
      }
    });
  }

  Future<void> _mergeAndSave() async {
    if (_frontPath == null || _backPath == null) return;

    setState(() => _isProcessing = true);

    final appDir = await DocumentStorageService.instance.appDirectory;
    final pagesDir = Directory('${appDir.path}/pages');
    if (!await pagesDir.exists()) await pagesDir.create(recursive: true);

    final pageId = const Uuid().v4();
    final outPath = '${pagesDir.path}/idcard_$pageId.jpg';

    final success = ArchScanBridge.instance.stitchIdCard(
      frontPath: _frontPath!,
      backPath: _backPath!,
      outputPath: outPath,
    );

    if (!success) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to stitch ID card sides')),
        );
      }
      return;
    }

    final now = DateTime.now();
    final scanPage = ScanPage(
      id: pageId,
      rawImagePath: _frontPath!,
      processedImagePath: outPath,
      corners: const [
        Point2D(0.0, 0.0),
        Point2D(1.0, 0.0),
        Point2D(1.0, 1.0),
        Point2D(0.0, 1.0),
      ],
      filter: ScanFilter.original,
    );

    final doc = ScanDocument(
      id: const Uuid().v4(),
      title: 'ID Card ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
      pages: [scanPage],
    );

    await DocumentStorageService.instance.saveDocument(doc);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DocumentDetailScreen(documentId: doc.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readyToStitch = _frontPath != null && _backPath != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('2-Sided ID Card Scan'),
      ),
      body: _isProcessing
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text(
                    'Place both sides of ID card inside the frames below',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? ArchTheme.darkTextSecondary
                          : ArchTheme.lightTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Front Card Slot
                  Expanded(
                    child: _buildCardSlot(
                      label: 'FRONT SIDE',
                      path: _frontPath,
                      onTap: () => _captureCard(true),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Back Card Slot
                  Expanded(
                    child: _buildCardSlot(
                      label: 'BACK SIDE',
                      path: _backPath,
                      onTap: () => _captureCard(false),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: readyToStitch ? _mergeAndSave : null,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Combine & Generate A4 Sheet'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCardSlot({
    required String label,
    required String? path,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: path != null
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: path != null ? 1.5 : 1.0,
          ),
        ),
        child: path != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(path), fit: BoxFit.cover),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.credit_card, size: 36, color: ArchTheme.textSecondary),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to capture $label',
                    style: const TextStyle(
                      color: ArchTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
