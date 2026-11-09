import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/arch_theme.dart';
import 'crop_screen.dart';

class CameraScanScreen extends StatefulWidget {
  final String? documentId;

  const CameraScanScreen({super.key, this.documentId});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  bool _isBatchMode = false;
  bool _flashOn = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _captureFromCamera() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
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

  Future<void> _pickFromGallery() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Document'),
        actions: [
          IconButton(
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: _flashOn ? ArchTheme.primary : Colors.white70,
            ),
            tooltip: 'Flash',
            onPressed: () {
              setState(() => _flashOn = !_flashOn);
            },
          ),
          IconButton(
            icon: Icon(
              _isBatchMode ? Icons.burst_mode : Icons.photo_camera,
              color: _isBatchMode ? ArchTheme.accent : Colors.white70,
            ),
            tooltip: _isBatchMode ? 'Batch Mode' : 'Single Page',
            onPressed: () {
              setState(() => _isBatchMode = !_isBatchMode);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Viewfinder background
          Container(
            color: const Color(0xFF0F172A),
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final glow = _pulseController.value * 0.3 + 0.7;
                  return CustomPaint(
                    size: const Size(300, 420),
                    painter: _ViewfinderOverlayPainter(
                      glowOpacity: glow,
                      color: ArchTheme.primary,
                    ),
                  );
                },
              ),
            ),
          ),
          // Viewfinder instruction
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isBatchMode
                    ? 'Batch Scan: capture consecutive pages'
                    : 'Position document within guide frame',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          // Bottom controls
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery button
                IconButton(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library, color: Colors.white, size: 28),
                  tooltip: 'Gallery',
                ),
                // Shutter button
                GestureDetector(
                  onTap: _captureFromCamera,
                  child: Container(
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ArchTheme.primary, width: 4),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Color(0xFF0B132B), size: 32),
                    ),
                  ),
                ),
                // Mode indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ArchTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isBatchMode ? 'BATCH' : 'SINGLE',
                    style: TextStyle(
                      color: _isBatchMode ? ArchTheme.accent : ArchTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderOverlayPainter extends CustomPainter {
  final double glowOpacity;
  final Color color;

  _ViewfinderOverlayPainter({required this.glowOpacity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final framePaint = Paint()
      ..color = color.withOpacity(0.3 * glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final cornerPaint = Paint()
      ..color = color.withOpacity(glowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(16),
    );
    canvas.drawRRect(rrect, framePaint);

    // Draw 4 corner reticles
    const len = 30.0;
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
  bool shouldRepaint(covariant _ViewfinderOverlayPainter oldDelegate) =>
      oldDelegate.glowOpacity != glowOpacity;
}
