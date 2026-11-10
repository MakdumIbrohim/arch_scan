import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../core/theme/arch_theme.dart';

class SignaturePadModal extends StatefulWidget {
  final ValueChanged<String>? onSignatureSaved;

  const SignaturePadModal({super.key, this.onSignatureSaved});

  @override
  State<SignaturePadModal> createState() => _SignaturePadModalState();
}

class _SignaturePadModalState extends State<SignaturePadModal> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  Future<ui.Image?> _captureSignature() async {
    if (_strokes.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(400, 200);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(size.width.toInt(), size.height.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Digital Signature',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: _clear,
                child: const Text('Clear', style: TextStyle(color: ArchTheme.danger)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ArchTheme.border, width: 1),
            ),
            child: GestureDetector(
              onPanStart: (d) {
                setState(() {
                  _currentStroke = [d.localPosition];
                  _strokes.add(_currentStroke);
                });
              },
              onPanUpdate: (d) {
                setState(() {
                  _currentStroke.add(d.localPosition);
                });
              },
              child: CustomPaint(
                painter: _SignaturePainter(strokes: _strokes),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                final img = await _captureSignature();
                if (img == null || !mounted) return;

                final byteData =
                    await img.toByteData(format: ui.ImageByteFormat.png);
                if (byteData == null || !mounted) return;

                final bytes = byteData.buffer.asUint8List();
                String savePath;
                try {
                  final tmpDir = await getTemporaryDirectory();
                  final file = File(
                      '${tmpDir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');
                  await file.writeAsBytes(bytes);
                  savePath = file.path;
                } catch (_) {
                  final file = File(
                      '.arch_scan_data/sig_${DateTime.now().millisecondsSinceEpoch}.png');
                  if (!file.parent.existsSync()) {
                    file.parent.createSync(recursive: true);
                  }
                  await file.writeAsBytes(bytes);
                  savePath = file.path;
                }

                if (!mounted) return;
                widget.onSignatureSaved?.call(savePath);
                nav.pop(savePath);
              },
              child: const Text('Save Signature'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
