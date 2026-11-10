import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../core/bridge/arch_scan_bridge.dart';

class EraseScreen extends StatefulWidget {
  final String imagePath;
  final ValueChanged<String>? onImageSaved;

  const EraseScreen({
    super.key,
    required this.imagePath,
    this.onImageSaved,
  });

  @override
  State<EraseScreen> createState() => _EraseScreenState();
}

class _EraseScreenState extends State<EraseScreen> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  double _strokeWidth = 24.0;
  bool _isProcessing = false;
  late String _currentImagePath;
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.imagePath;
  }

  void _clearStrokes() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  Future<void> _applyErase() async {
    if (_strokes.isEmpty) return;

    final renderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    setState(() => _isProcessing = true);

    try {
      // 1. Generate binary mask matching renderBox size
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Black background (unmasked)
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black,
      );

      // White strokes (masked area to inpaint)
      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      for (final stroke in _strokes) {
        for (int i = 0; i < stroke.length - 1; i++) {
          canvas.drawLine(stroke[i], stroke[i + 1], strokePaint);
        }
      }

      final pic = recorder.endRecording();
      final maskImg = await pic.toImage(size.width.toInt(), size.height.toInt());
      final byteData =
          await maskImg.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to generate mask buffer');
      }

      final tmpDir = await getTemporaryDirectory();
      final maskPath =
          '${tmpDir.path}/mask_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(maskPath).writeAsBytes(byteData.buffer.asUint8List());

      // 2. Output destination for inpainted image
      final outPath =
          '${tmpDir.path}/erased_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // 3. Call Rust native Fast Marching inpainting engine asynchronously via compute/isolate to prevent UI thread lock
      final success = await Future.microtask(() => ArchScanBridge.instance.inpaintMask(
            basePath: _currentImagePath,
            maskPath: maskPath,
            outputPath: outPath,
          ));

      if (success && File(outPath).existsSync()) {
        setState(() {
          _currentImagePath = outPath;
          _strokes.clear();
          _currentStroke.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Objek / coretan berhasil dihapus!'),
              duration: Duration(milliseconds: 900),
            ),
          );
        }
      } else {
        throw Exception('Inpainting algorithm returned non-zero code');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _finishAndSave() {
    widget.onImageSaved?.call(_currentImagePath);
    Navigator.of(context).pop(_currentImagePath);
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF10B981);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Hapus Cerdas (Inpainting)',
            style: TextStyle(fontSize: 16, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white70),
            tooltip: 'Hapus Coretan Kuas',
            onPressed: _strokes.isNotEmpty ? _clearStrokes : null,
          ),
          IconButton(
            icon: const Icon(Icons.check, color: teal),
            tooltip: 'Simpan',
            onPressed: _finishAndSave,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top instruction guidance banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF27272A),
            child: Row(
              children: const [
                Icon(Icons.brush, color: teal, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Usap jari di atas objek, jempol, atau coretan yang ingin dihilangkan',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Main Interactive Canvas Area
          Expanded(
            child: Center(
              child: _isProcessing
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(color: teal),
                        SizedBox(height: 16),
                        Text(
                          'Merekontruksi tekstur piksel dokumen...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GestureDetector(
                          key: _imageKey,
                          onPanStart: (details) {
                            setState(() {
                              _currentStroke = [details.localPosition];
                              _strokes.add(_currentStroke);
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              _currentStroke.add(details.localPosition);
                            });
                          },
                          onPanEnd: (_) => setState(() {}),
                          child: Stack(
                            fit: StackFit.passthrough,
                            children: [
                              Image.file(
                                File(_currentImagePath),
                                fit: BoxFit.contain,
                              ),
                              CustomPaint(
                                painter: _BrushPainter(
                                  strokes: _strokes,
                                  strokeWidth: _strokeWidth,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // Bottom Brush Controls Bar
          Container(
            color: const Color(0xFF18181B),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 12, color: Colors.white70),
                Expanded(
                  child: Slider(
                    value: _strokeWidth,
                    min: 10.0,
                    max: 50.0,
                    activeColor: teal,
                    inactiveColor: Colors.white24,
                    onChanged: (val) => setState(() => _strokeWidth = val),
                  ),
                ),
                const Icon(Icons.circle, size: 24, color: Colors.white70),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _strokes.isNotEmpty && !_isProcessing
                      ? _applyErase
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                  ),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Hapus Objek'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final double strokeWidth;

  _BrushPainter({required this.strokes, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x9910B981) // Semi-transparent teal mask preview
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BrushPainter oldDelegate) => true;
}
