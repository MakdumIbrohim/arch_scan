import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
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

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _permissionDenied = false;
  String? _errorMessage;

  final ImagePicker _picker = ImagePicker();
  final List<String> _batchQueue = [];
  bool _isBatchMode = false;
  bool _flashOn = false;
  bool _isTakingPicture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameraWithPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCameraController(cameraController.description);
    }
  }

  Future<void> _initCameraWithPermission() async {
    // 1. Explicitly check & request Camera permission
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _errorMessage = 'Izin kamera belum diberikan.';
        });
      }
      return;
    }

    // 2. Discover available cameras on device
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Tidak ada hardware kamera terdeteksi.';
          });
        }
        return;
      }

      final rearCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      await _initCameraController(rearCamera);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal inisialisasi kamera: $e';
        });
      }
    }
  }

  Future<void> _initCameraController(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    _controller = controller;

    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _permissionDenied = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal membuka kamera: $e';
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final nextState = !_flashOn;
      await _controller!.setFlashMode(
        nextState ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() {
          _flashOn = nextState;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Flash tidak didukung: $e')),
        );
      }
    }
  }

  Future<void> _captureImage() async {
    if (_isTakingPicture) return;

    String? capturedPath;

    if (_controller != null && _controller!.value.isInitialized) {
      try {
        setState(() => _isTakingPicture = true);
        final XFile file = await _controller!.takePicture();
        capturedPath = file.path;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengambil foto: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isTakingPicture = false);
      }
    } else {
      // Fallback for emulator / desktop
      final picked = await _picker.pickImage(source: ImageSource.camera);
      capturedPath = picked?.path;
    }

    if (capturedPath == null || !mounted) return;

    if (_isBatchMode) {
      setState(() {
        _batchQueue.add(capturedPath!);
      });
    } else {
      // Turn off torch when navigating to crop
      if (_flashOn && _controller != null) {
        try {
          await _controller!.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CropScreen(
            imagePath: capturedPath!,
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
      if (_flashOn && _controller != null) {
        try {
          await _controller!.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      if (!mounted) return;
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
    if (_flashOn && _controller != null) {
      try {
        _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}
    }

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
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isBatchMode ? 'Batch Scanner' : 'Document Scanner',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: _flashOn ? Colors.amber : Colors.white,
            ),
            tooltip: 'Flashlight (Senter)',
            onPressed: _toggleFlash,
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _isBatchMode = !_isBatchMode;
                _batchQueue.clear();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isBatchMode ? ArchTheme.primary : Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _isBatchMode ? 'BATCH' : 'SINGLE',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live hardware camera preview (if initialized)
          if (_isCameraInitialized && _controller != null)
            Positioned.fill(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize?.height ?? 1,
                      height: _controller!.value.previewSize?.width ?? 1,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),
            )
          else if (_permissionDenied)
            // Permission request UI card
            Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      size: 54,
                      color: ArchTheme.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Izin Kamera Diperlukan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'ArchScan memerlukan izin kamera agar dapat memindai dokumen dan mengaktifkan lampu senter secara langsung.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final res = await Permission.camera.request();
                        if (res.isGranted) {
                          _initCameraWithPermission();
                        } else if (res.isPermanentlyDenied) {
                          await openAppSettings();
                        }
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Beri Izin Kamera'),
                    ),
                  ],
                ),
              ),
            )
          else
            // Fallback / Loading camera state
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    const Icon(Icons.videocam_off_outlined,
                        size: 48, color: Colors.white54),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Pilih dari Galeri'),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(color: ArchTheme.primary),
                    const SizedBox(height: 16),
                    const Text(
                      'Membuka kamera hardware...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),

          // 2. Viewfinder Reticle Overlay
          Center(
            child: CustomPaint(
              size: const Size(280, 390),
              painter: _MinimalViewfinderPainter(),
            ),
          ),

          // 3. Document framing guidance message
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isBatchMode
                      ? 'Mode Batch: ${_batchQueue.length} halaman terambil'
                      : 'Posisikan dokumen di dalam garis retikel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // 4. Mode Selector Bar (Dokumen / Batch / Kartu ID)
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
                const SizedBox(width: 20),
                _buildModeChoice('Batch', _isBatchMode, () {
                  setState(() => _isBatchMode = true);
                }),
                const SizedBox(width: 20),
                _buildModeChoice('Kartu ID', false, () {
                  if (_flashOn && _controller != null) {
                    try {
                      _controller!.setFlashMode(FlashMode.off);
                    } catch (_) {}
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IdCardScanScreen()),
                  );
                }),
              ],
            ),
          ),

          // 5. Bottom Controls
          Positioned(
            bottom: 28,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gallery button
                IconButton(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined,
                      color: Colors.white, size: 28),
                  tooltip: 'Galeri',
                ),

                // Shutter button (clean double circle)
                GestureDetector(
                  onTap: _isTakingPicture ? null : _captureImage,
                  child: Container(
                    width: 74,
                    height: 74,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isTakingPicture ? Colors.grey : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: _isTakingPicture
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              ),
                            )
                          : null,
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
                            color: ArchTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              '${_batchQueue.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
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

    final boxPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), boxPaint);

    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const len = 24.0;
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
