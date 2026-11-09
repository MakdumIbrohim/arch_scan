import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/arch_theme.dart';
import 'crop_screen.dart';
import 'batch_process_screen.dart';
import 'id_card_scan_screen.dart';

class CameraScanScreen extends StatefulWidget {
  final String? documentId;

  const CameraScanScreen({super.key, this.documentId});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<String> _batchQueue = [];
  bool _isBatchMode = false;
  bool _flashOn = false;

  Future<void> _captureImage() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;

    if (_isBatchMode) {
      setState(() {
        _batchQueue.add(picked.path);
      });
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CropScreen(
            imagePath: picked.path,
            documentId: widget.documentId,
          ),
        ),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isBatchMode) {
      final pickedList = await _picker.pickMultiImage();
      if (pickedList.isEmpty || !mounted) return;
      setState(() {
        _batchQueue.addAll(pickedList.map((e) => e.path));
      });
    } else {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CropScreen(
            imagePath: picked.path,
            documentId: widget.documentId,
          ),
        ),
      );
    }
  }

  void _finishBatch() {
    if (_batchQueue.isEmpty) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BatchProcessScreen(
          imagePaths: List.from(_batchQueue),
          documentId: widget.documentId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_isBatchMode ? 'Batch Scanner' : 'Document Scanner'),
        actions: [
          IconButton(
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            tooltip: 'Flash',
            onPressed: () => setState(() => _flashOn = !_flashOn),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _isBatchMode = !_isBatchMode;
                _batchQueue.clear();
              });
            },
            child: Text(
              _isBatchMode ? 'BATCH' : 'SINGLE',
              style: TextStyle(
                color: _isBatchMode ? ArchTheme.accent : Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Minimalist Viewfinder Area
          Center(
            child: CustomPaint(
              size: const Size(280, 390),
              painter: _MinimalViewfinderPainter(),
            ),
          ),
          // Clean HUD Instruction
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: ArchTheme.border, width: 1),
                ),
                child: Text(
                  _isBatchMode
                      ? 'Batch Mode: ${_batchQueue.length} page(s) captured'
                      : 'Align document within borders',
                  style: const TextStyle(
                    color: ArchTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          // Mode Selector Bar (Dokumen / Batch / Kartu ID)
          Positioned(
            bottom: 115,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildModeChoice('Dokumen', !_isBatchMode, () {
                  setState(() => _isBatchMode = false);
                }),
                const SizedBox(width: 24),
                _buildModeChoice('Batch', _isBatchMode, () {
                  setState(() => _isBatchMode = true);
                }),
                const SizedBox(width: 24),
                _buildModeChoice('Kartu ID', false, () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IdCardScanScreen()),
                  );
                }),
              ],
            ),
          ),
          // Bottom Controls
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gallery button
                IconButton(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined,
                      color: Colors.white, size: 26),
                  tooltip: 'Gallery',
                ),
                // Shutter button (clean double circle)
                GestureDetector(
                  onTap: _captureImage,
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                // Batch finish button or empty spacer
                _isBatchMode && _batchQueue.isNotEmpty
                    ? GestureDetector(
                        onTap: _finishBatch,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: ArchTheme.surfaceMuted,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ArchTheme.border, width: 1),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.file(
                                File(_batchQueue.last),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                              Container(
                                color: Colors.black54,
                                child: Center(
                                  child: Text(
                                    '${_batchQueue.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChoice(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _MinimalViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Subtle 1px boundary box
    final boxPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), boxPaint);

    // Sharp 2px white corner brackets
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const len = 20.0;
    // Top-Left
    canvas.drawLine(const Offset(0, len), const Offset(0, 0), cornerPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(len, 0), cornerPaint);
    // Top-Right
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), cornerPaint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), cornerPaint);
    // Bottom-Right
    canvas.drawLine(Offset(w, h - len), Offset(w, h), cornerPaint);
    canvas.drawLine(Offset(w, h), Offset(w - len, h), cornerPaint);
    // Bottom-Left
    canvas.drawLine(Offset(len, h), Offset(0, h), cornerPaint);
    canvas.drawLine(Offset(0, h), Offset(0, h - len), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _MinimalViewfinderPainter oldDelegate) => false;
}
