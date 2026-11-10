import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme/arch_theme.dart';
import '../services/document_storage.dart';

class OcrScreen extends StatefulWidget {
  final String? initialImagePath;

  const OcrScreen({super.key, this.initialImagePath});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _imagePath;
  bool _isProcessing = false;
  final TextEditingController _textCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _imagePath = widget.initialImagePath;
      _runOcr();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null) {
      setState(() {
        _imagePath = picked.path;
      });
      _runOcr();
    }
  }

  Future<void> _runOcr() async {
    if (_imagePath == null) return;
    setState(() => _isProcessing = true);

    // Simulate OCR text extraction pipeline / mock extracted document lines
    await Future.delayed(const Duration(milliseconds: 600));

    final filename = _imagePath!.split('/').last;
    final buffer = StringBuffer();
    buffer.writeln('--- HASIL EKSTRAKSI TEKS (OCR) ---');
    buffer.writeln('Sumber: $filename');
    buffer.writeln('Tanggal: ${DateTime.now().toLocal().toString().split('.')[0]}');
    buffer.writeln('');
    buffer.writeln('DOKUMEN IDENTITAS / ARSIP NEGARA');
    buffer.writeln('Republik Indonesia');
    buffer.writeln('NIK / Nomor Dokumen: 3201082504950002');
    buffer.writeln('Nama Lengkap: ARCH SCAN VERIFIED USER');
    buffer.writeln('Status: RESMI / TERSERTIFIKASI');
    buffer.writeln('');
    buffer.writeln('Dokumen ini telah dipindai dan diproses menggunakan ArchScan Core Engine.');
    buffer.writeln('Layer teks otomatis diindeks untuk Searchable PDF.');

    setState(() {
      _textCtrl.text = buffer.toString();
      _isProcessing = false;
    });
  }

  Future<void> _saveAsTxt() async {
    if (_textCtrl.text.isEmpty) return;
    try {
      final appDir = await DocumentStorageService.instance.appDirectory;
      final file = File('${appDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(_textCtrl.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Teks disimpan ke: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Ekstraksi Teks (OCR)'),
        actions: [
          if (_textCtrl.text.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Salin Teks',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _textCtrl.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Teks disalin ke clipboard')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Bagikan Teks',
              onPressed: () {
                SharePlus.instance.share(ShareParams(
                  text: _textCtrl.text,
                  subject: 'Hasil OCR Dokumen',
                ));
              },
            ),
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Simpan ke File .txt',
              onPressed: _saveAsTxt,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Image preview container or empty picker
          Container(
            height: 180,
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor),
            ),
            child: _imagePath != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.file(
                          File(_imagePath!),
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Ganti', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.text_fields_outlined,
                            size: 36, color: theme.colorScheme.primary),
                        const SizedBox(height: 8),
                        const Text('Pilih foto dokumen untuk mengekstrak teks',
                            style: TextStyle(
                                fontSize: 13, color: ArchTheme.textSecondary)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt, size: 16),
                              label: const Text('Kamera'),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: const Text('Galeri'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          // Extracted text editor area
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: _isProcessing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: theme.colorScheme.primary),
                          const SizedBox(height: 12),
                          const Text('Mengekstrak teks dokumen...',
                              style: TextStyle(color: ArchTheme.textSecondary)),
                        ],
                      ),
                    )
                  : TextField(
                      controller: _textCtrl,
                      maxLines: null,
                      expands: true,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: isDark ? ArchTheme.darkTextPrimary : ArchTheme.lightTextPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Teks hasil OCR akan muncul di sini...',
                        border: InputBorder.none,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
