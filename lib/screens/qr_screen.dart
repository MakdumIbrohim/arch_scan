import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  bool _flashOn = false;
  String? _scannedResult;
  String? _imagePath;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        _imagePath = picked.path;
        // Decode simulated QR/Barcode content
        _scannedResult = 'https://hermes-agent.nousresearch.com/docs/arch-scan-v1';
      });
    }
  }

  void _onSimulateScan() {
    setState(() {
      _scannedResult = 'https://github.com/makdumibrohim/arch_scan';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Scan QR & Barcode', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: _flashOn ? Colors.amber : Colors.white,
            ),
            tooltip: 'Flashlight',
            onPressed: () => setState(() => _flashOn = !_flashOn),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background viewfinder representation
          if (_imagePath != null)
            Positioned.fill(
              child: Image.file(
                File(_imagePath!),
                fit: BoxFit.cover,
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: const Color(0xFF111827),
                child: const Center(
                  child: Icon(
                    Icons.qr_code_2_outlined,
                    size: 140,
                    color: Colors.white12,
                  ),
                ),
              ),
            ),

          // Central targeting reticle & scanning laser
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(260, 260),
                    painter: _QrReticlePainter(color: theme.colorScheme.primary),
                  ),
                  AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (context, child) {
                      return Positioned(
                        top: 250 * _animCtrl.value,
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(alpha: 0.8),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Top guidance text
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Arahkan kamera ke Kode QR atau Barcode',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),

          // Bottom result card or action bar
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _scannedResult != null
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.primary),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Hasil Pindaian',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setState(() => _scannedResult = null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          _scannedResult!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: _scannedResult!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Teks disalin ke clipboard')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Salin'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  SharePlus.instance.share(ShareParams(
                                    text: _scannedResult!,
                                    subject: 'Hasil Scan QR',
                                  ));
                                },
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('Bagikan'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        tooltip: 'Pilih dari Galeri',
                      ),
                      FloatingActionButton(
                        onPressed: _onSimulateScan,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(Icons.qr_code_scanner, color: Colors.white),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        tooltip: 'Buka Kamera',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QrReticlePainter extends CustomPainter {
  final Color color;
  const _QrReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const len = 28.0;
    // Top-Left
    canvas.drawLine(const Offset(0, len), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(len, 0), paint);
    // Top-Right
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    // Bottom-Right
    canvas.drawLine(Offset(w, h - len), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w - len, h), paint);
    // Bottom-Left
    canvas.drawLine(Offset(len, h), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - len), paint);
  }

  @override
  bool shouldRepaint(covariant _QrReticlePainter oldDelegate) =>
      oldDelegate.color != color;
}
