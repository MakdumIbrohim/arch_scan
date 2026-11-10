import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final ImagePicker _picker = ImagePicker();
  String? _scannedResult;
  bool _flashOn = false;
  String _activeTab = 'Telusuri'; // 'Telusuri', 'Terjemahan', 'Bicara', 'Buat'

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scannedResult != null) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawVal = barcode.rawValue ?? barcode.displayValue;
      if (rawVal != null && rawVal.trim().isNotEmpty) {
        HapticFeedback.mediumImpact();
        setState(() {
          _scannedResult = rawVal.trim();
        });
        break;
      }
    }
  }

  Future<void> _pickImageAndAnalyze() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    try {
      final BarcodeCapture? capture = await _controller.analyzeImage(picked.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final rawVal = capture.barcodes.first.rawValue ??
            capture.barcodes.first.displayValue;
        if (rawVal != null && rawVal.trim().isNotEmpty) {
          setState(() {
            _scannedResult = rawVal.trim();
          });
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada Kode QR / Barcode terdeteksi pada gambar'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menganalisis gambar: $e')),
        );
      }
    }
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _flashOn = !_flashOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Live hardware camera feed
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),

          // 2. Google Lens Header: [←]  [⚡]  Google Lens                 [⋮]
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    IconButton(
                      icon: Icon(
                        _flashOn ? Icons.flash_on : Icons.flash_off,
                        color: _flashOn ? Colors.amber : Colors.white,
                        size: 22,
                      ),
                      tooltip: 'Lampu Kilat',
                      onPressed: _toggleTorch,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Google Lens',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Center Target Reticle & Interactive Tooltip
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clean rounded white bounding box
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white, width: 2.0),
                  ),
                ),
                const SizedBox(height: 18),
                // Google Lens Instruction Tooltip
                if (_scannedResult == null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xCC202124),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Text(
                      'Arahkan kamera ke Kode QR\nuntuk menelusuri',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 4. Detected Link Chip floating above result (if scanned)
          if (_scannedResult != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.46,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE63C4043),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public, color: Color(0xFF8AB4F8), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _scannedResult!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _scannedResult!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Tautan disalin ke clipboard')),
                          );
                        },
                        child: const Icon(Icons.copy, color: Colors.white70, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 5. Google Lens Shutter Area
          Positioned(
            bottom: 96,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Tombol Galeri (Lingkaran hitam border putih)
                GestureDetector(
                  onTap: _pickImageAndAnalyze,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                    child: const Icon(Icons.photo_outlined, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 38),

                // Shutter Utama Google Lens (Lingkaran putih solid dengan ikon loop kaca pembesar)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                  },
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.search, color: Colors.black, size: 34),
                    ),
                  ),
                ),
                const SizedBox(width: 88), // Imbangi jarak galeri di kiri agar shutter tepat di tengah
              ],
            ),
          ),

          // 6. Google Lens Bottom Mode Dock: [ Telusuri | Terjemahan | Bicara | Buat ]
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xE6202124), // Dark translucent pill dock
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white10),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLensTab(
                        label: 'Telusuri',
                        icon: Icons.search,
                        isSelected: _activeTab == 'Telusuri',
                        onTap: () => setState(() => _activeTab = 'Telusuri'),
                      ),
                      _buildLensTab(
                        label: 'Terjemahan',
                        icon: Icons.translate,
                        isSelected: _activeTab == 'Terjemahan',
                        onTap: () {
                          setState(() => _activeTab = 'Terjemahan');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mode Terjemahan siap'),
                              duration: Duration(milliseconds: 700),
                            ),
                          );
                        },
                      ),
                      _buildLensTab(
                        label: 'Bicara',
                        icon: Icons.graphic_eq,
                        isSelected: _activeTab == 'Bicara',
                        onTap: () {
                          setState(() => _activeTab = 'Bicara');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mode Baca Suara siap'),
                              duration: Duration(milliseconds: 700),
                            ),
                          );
                        },
                      ),
                      _buildLensTab(
                        label: 'Buat',
                        icon: Icons.edit_note,
                        isSelected: _activeTab == 'Buat',
                        onTap: () {
                          setState(() => _activeTab = 'Buat');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mode Buat Catatan siap'),
                              duration: Duration(milliseconds: 700),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 7. Bottom Result Action Modal (jika QR terdeteksi)
          if (_scannedResult != null)
            Positioned(
              bottom: 185,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xF0202124),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF8AB4F8), width: 1.2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Hasil Pindaian Nyata',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _scannedResult!,
                            style: const TextStyle(
                              color: Color(0xFF8AB4F8),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white, size: 20),
                      onPressed: () {
                        SharePlus.instance.share(
                          ShareParams(text: _scannedResult!, subject: 'Hasil Scan QR'),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () => setState(() => _scannedResult = null),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLensTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF444746) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFE3E3E3),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
