import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/signature_pad.dart';
import 'crop_screen.dart';
import 'batch_process_screen.dart';
import 'id_card_scan_screen.dart';
import 'qr_screen.dart';

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
  bool _isBatchMode = true; // Default: 'Beberapa Halaman' as in CamScanner reference
  FlashMode _flashMode = FlashMode.off;
  bool _isTakingPicture = false;
  bool _autoEnhance = true;
  ResolutionPreset _currentResolution = ResolutionPreset.veryHigh;
  String _activeMode = 'Scan'; // 'Kode QR', 'Tanda tangani', 'Scan', 'Hapus Cerdas', 'Kartu ID'

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
      _currentResolution,
      enableAudio: false,
    );

    _controller = controller;

    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
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

  Future<void> _cycleFlashMode() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      FlashMode next;
      switch (_flashMode) {
        case FlashMode.off:
          next = FlashMode.torch;
          break;
        case FlashMode.torch:
          next = FlashMode.auto;
          break;
        case FlashMode.auto:
          next = FlashMode.always;
          break;
        default:
          next = FlashMode.off;
          break;
      }
      await _controller!.setFlashMode(next);
      if (mounted) {
        setState(() => _flashMode = next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flash: ${next.name.toUpperCase()}'),
            duration: const Duration(milliseconds: 700),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Flash tidak didukung: $e')),
        );
      }
    }
  }

  Future<void> _cycleResolution() async {
    if (_controller == null) return;
    ResolutionPreset next;
    String label;
    if (_currentResolution == ResolutionPreset.veryHigh ||
        _currentResolution == ResolutionPreset.max) {
      next = ResolutionPreset.high;
      label = 'HD (Standard)';
    } else {
      next = ResolutionPreset.veryHigh;
      label = 'HD+ (Ultra Clear)';
    }

    setState(() => _currentResolution = next);
    await _initCameraController(_controller!.description);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resolusi Kamera: $label'),
          duration: const Duration(milliseconds: 700),
        ),
      );
    }
  }

  void _showCameraSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pengaturan Kamera',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  _autoEnhance ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                  color: const Color(0xFF10B981),
                ),
                title: const Text('Penyempurnaan Otomatis (Magic Color)',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                trailing: Switch(
                  value: _autoEnhance,
                  activeThumbColor: const Color(0xFF10B981),
                  onChanged: (val) {
                    setState(() => _autoEnhance = val);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.hd_outlined, color: Colors.white70),
                title: const Text('Kualitas Bidik',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(
                  _currentResolution == ResolutionPreset.veryHigh
                      ? 'Ultra High'
                      : 'High',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _cycleResolution();
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.white70),
                title: const Text('Reset Pengaturan Kamera',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  setState(() {
                    _autoEnhance = true;
                    _currentResolution = ResolutionPreset.veryHigh;
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
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
      final picked = await _picker.pickImage(source: ImageSource.camera);
      capturedPath = picked?.path;
    }

    if (capturedPath == null || !mounted) return;

    if (_isBatchMode) {
      setState(() {
        _batchQueue.add(capturedPath!);
      });
    } else {
      if (_flashMode == FlashMode.torch && _controller != null) {
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
      if (_flashMode == FlashMode.torch && _controller != null) {
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

  Future<void> _importDocumentFiles() async {
    await _pickFromGallery();
  }

  void _finishBatch() {
    if (_batchQueue.isEmpty) return;
    if (_flashMode == FlashMode.torch && _controller != null) {
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

  void _showAllFeaturesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Semua Fitur Pindai',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                children: [
                  _buildFeatureIcon(
                    icon: Icons.document_scanner,
                    label: 'Scan Dokumen',
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _activeMode = 'Scan');
                    },
                  ),
                  _buildFeatureIcon(
                    icon: Icons.qr_code_scanner,
                    label: 'Kode QR',
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const QrScannerScreen()),
                      );
                    },
                  ),
                  _buildFeatureIcon(
                    icon: Icons.credit_card,
                    label: 'Kartu ID',
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const IdCardScanScreen()),
                      );
                    },
                  ),
                  _buildFeatureIcon(
                    icon: Icons.draw_outlined,
                    label: 'Tanda Tangan',
                    onTap: () {
                      Navigator.pop(ctx);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const SignaturePadModal(),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF10B981), size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _onModeSelected(String mode) {
    if (mode == _activeMode) return;
    setState(() => _activeMode = mode);

    if (mode == 'Kode QR') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QrScannerScreen()),
      ).then((_) {
        if (mounted) setState(() => _activeMode = 'Scan');
      });
    } else if (mode == 'Kartu ID') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IdCardScanScreen()),
      ).then((_) {
        if (mounted) setState(() => _activeMode = 'Scan');
      });
    } else if (mode == 'Tanda tangani') {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const SignaturePadModal(),
      ).then((_) {
        if (mounted) setState(() => _activeMode = 'Scan');
      });
    } else if (mode == 'Hapus Cerdas') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mode Hapus Cerdas: Siap membersihkan dokumen otomatis.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flashlight_on;
      default:
        return Icons.flash_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    const tealAccent = Color(0xFF10B981);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live hardware camera preview (polos tanpa garis reticle seperti di CamScanner asli)
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
                      color: tealAccent,
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.settings),
                      label: const Text('Beri Izin Kamera'),
                    ),
                  ],
                ),
              ),
            )
          else
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
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Pilih dari Galeri'),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(color: tealAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'Membuka kamera hardware...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),

          // 2. Header Atas: [X]  [Flash]  [Auto-Enhance]  [HD]  [Menu 3-titik]
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button (X)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Tutup',
                    ),

                    // Right control group: Flash, Enhance, HD, Menu
                    Row(
                      children: [
                        // Flash mode cycle
                        IconButton(
                          icon: Icon(
                            _getFlashIcon(),
                            color: _flashMode == FlashMode.off
                                ? Colors.white
                                : Colors.amber,
                            size: 22,
                          ),
                          tooltip: 'Lampu Kilat',
                          onPressed: _cycleFlashMode,
                        ),
                        const SizedBox(width: 8),

                        // Auto-enhance filter toggle
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _autoEnhance ? tealAccent : Colors.white60,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.auto_fix_high,
                              color: _autoEnhance ? tealAccent : Colors.white,
                              size: 16,
                            ),
                          ),
                          tooltip: 'Penyempurnaan Otomatis',
                          onPressed: () {
                            setState(() => _autoEnhance = !_autoEnhance);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_autoEnhance
                                    ? 'Penyempurnaan Otomatis: AKTIF'
                                    : 'Penyempurnaan Otomatis: NONAKTIF'),
                                duration: const Duration(milliseconds: 700),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),

                        // HD resolution badge button
                        GestureDetector(
                          onTap: _cycleResolution,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white70, width: 1.2),
                            ),
                            child: const Text(
                              'HD',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 3-dot overflow menu
                        IconButton(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white, size: 24),
                          tooltip: 'Pengaturan Lanjutan',
                          onPressed: _showCameraSettingsMenu,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating Pill Selector: [ Satu Halaman | Beberapa Halaman ]
          Positioned(
            bottom: 155,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xCC18181B), // Translucent dark
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPillOption(
                      label: 'Satu Halaman',
                      isSelected: !_isBatchMode,
                      onTap: () {
                        setState(() {
                          _isBatchMode = false;
                          _batchQueue.clear();
                        });
                      },
                    ),
                    _buildPillOption(
                      label: 'Beberapa Halaman',
                      isSelected: _isBatchMode,
                      onTap: () {
                        setState(() => _isBatchMode = true);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Horizontal Feature Carousel Bar: [ Kode QR | Tanda tangani | Scan | Hapus Cerdas | Kartu ID ]
          Positioned(
            bottom: 102,
            left: 0,
            right: 0,
            child: Container(
              height: 38,
              alignment: Alignment.center,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildCarouselItem(
                      label: 'Kode QR',
                      hasBadge: true,
                      isSelected: _activeMode == 'Kode QR',
                      onTap: () => _onModeSelected('Kode QR'),
                    ),
                    const SizedBox(width: 24),
                    _buildCarouselItem(
                      label: 'Tanda tangani',
                      hasBadge: true,
                      isSelected: _activeMode == 'Tanda tangani',
                      onTap: () => _onModeSelected('Tanda tangani'),
                    ),
                    const SizedBox(width: 24),
                    _buildCarouselItem(
                      label: 'Scan',
                      hasBadge: false,
                      isSelected: _activeMode == 'Scan',
                      onTap: () => _onModeSelected('Scan'),
                    ),
                    const SizedBox(width: 24),
                    _buildCarouselItem(
                      label: 'Hapus Cerdas',
                      hasBadge: false,
                      isSelected: _activeMode == 'Hapus Cerdas',
                      onTap: () => _onModeSelected('Hapus Cerdas'),
                    ),
                    const SizedBox(width: 24),
                    _buildCarouselItem(
                      label: 'Kartu ID',
                      hasBadge: false,
                      isSelected: _activeMode == 'Kartu ID',
                      onTap: () => _onModeSelected('Kartu ID'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Bottom Shutter Bar: [Semua Fitur]  ( SHUTTER )  [Impor Gambar]  [Impor File]
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                height: 96,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Kiri: Semua Fitur (Grid 9-dots)
                    GestureDetector(
                      onTap: _showAllFeaturesModal,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.apps, color: Colors.white, size: 26),
                          SizedBox(height: 4),
                          Text(
                            'Semua Fitur',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Tengah: Shutter Button dengan Ring Hijau Toska
                    GestureDetector(
                      onTap: _isTakingPicture ? null : _captureImage,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tealAccent,
                            width: 3.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isTakingPicture
                                ? Colors.grey
                                : Colors.white,
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

                    // Kanan: Impor Gambar & Impor File (atau Tombol Selesai Batch jika ada antrean)
                    _isBatchMode && _batchQueue.isNotEmpty
                        ? GestureDetector(
                            onTap: _finishBatch,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: tealAccent,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${_batchQueue.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Text(
                                    'Selesai',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              // Impor Gambar
                              GestureDetector(
                                onTap: _pickFromGallery,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.photo_outlined,
                                          color: Colors.white, size: 24),
                                      SizedBox(height: 4),
                                      Text(
                                        'Impor Gambar',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Impor File
                              GestureDetector(
                                onTap: _importDocumentFiles,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.description_outlined,
                                          color: Colors.white, size: 24),
                                      SizedBox(height: 4),
                                      Text(
                                        'Impor File',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3F3F46) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCarouselItem({
    required String label,
    required bool hasBadge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const teal = Color(0xFF10B981);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? teal : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  letterSpacing: 0.3,
                ),
              ),
              if (hasBadge) ...[
                const SizedBox(width: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444), // Red notification dot
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Teal active indicator bar
          Container(
            width: isSelected ? 16 : 0,
            height: 2.5,
            decoration: BoxDecoration(
              color: isSelected ? teal : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
