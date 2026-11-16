import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme/arch_theme.dart';
import '../services/document_storage.dart';

enum OcrDisplayMode { text, table }

class OcrScreen extends StatefulWidget {
  final String? initialImagePath;

  const OcrScreen({super.key, this.initialImagePath});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  String? _imagePath;
  bool _isProcessing = false;
  final TextEditingController _textCtrl = TextEditingController();
  OcrDisplayMode _displayMode = OcrDisplayMode.text;
  List<List<String>> _tableData = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _imagePath = widget.initialImagePath;
      _runOcr();
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _textCtrl.dispose();
    super.dispose();
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

    try {
      final inputImage = InputImage.fromFilePath(_imagePath!);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // 1. Plain text extraction
      final fullText = recognizedText.text.trim();

      // 2. Tabular extraction based on 2D bounding box spatial clustering
      final table = _parseTabularStructure(recognizedText);

      if (mounted) {
        setState(() {
          if (fullText.isEmpty) {
            _textCtrl.text = 'Tidak ada teks yang terdeteksi pada gambar ini.';
            _tableData = [];
          } else {
            _textCtrl.text = fullText;
            _tableData = table;
          }
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _textCtrl.text = 'Gagal memproses OCR: $e';
          _isProcessing = false;
        });
      }
    }
  }

  List<List<String>> _parseTabularStructure(RecognizedText recognizedText) {
    final allLines = <TextLine>[];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    if (allLines.isEmpty) return [];

    // Sort lines primarily top-to-bottom
    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // Group into horizontal row bands
    final rows = <List<TextLine>>[];
    for (final line in allLines) {
      bool addedToRow = false;
      for (final row in rows) {
        final rowAvgTop =
            row.map((l) => l.boundingBox.top).reduce((a, b) => a + b) /
                row.length;
        final rowAvgHeight =
            row.map((l) => l.boundingBox.height).reduce((a, b) => a + b) /
                row.length;
        final diff = (line.boundingBox.top - rowAvgTop).abs();

        if (diff <= (rowAvgHeight * 0.75).clamp(12.0, 45.0)) {
          row.add(line);
          addedToRow = true;
          break;
        }
      }
      if (!addedToRow) {
        rows.add([line]);
      }
    }

    // In each row band, sort left-to-right and split by whitespace gaps
    final resultTable = <List<String>>[];
    int maxCols = 0;

    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      final rowCells = <String>[];

      for (final line in row) {
        if (line.elements.length > 1) {
          String currentCell = line.elements.first.text;
          double prevRight = line.elements.first.boundingBox.right;

          for (int i = 1; i < line.elements.length; i++) {
            final elem = line.elements[i];
            final gap = elem.boundingBox.left - prevRight;

            // Noticeable column gap threshold
            if (gap > 22.0) {
              rowCells.add(currentCell.trim());
              currentCell = elem.text;
            } else {
              currentCell += ' ${elem.text}';
            }
            prevRight = elem.boundingBox.right;
          }
          if (currentCell.trim().isNotEmpty) {
            rowCells.add(currentCell.trim());
          }
        } else {
          rowCells.add(line.text.trim());
        }
      }

      if (rowCells.isNotEmpty) {
        resultTable.add(rowCells);
        if (rowCells.length > maxCols) maxCols = rowCells.length;
      }
    }

    // Normalize column counts
    for (final r in resultTable) {
      while (r.length < maxCols) {
        r.add('');
      }
    }

    return resultTable;
  }

  Future<void> _saveAsTxt() async {
    if (_textCtrl.text.isEmpty) return;
    try {
      final appDir = await DocumentStorageService.instance.appDirectory;
      final file = File(
          '${appDir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.txt');
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

  Future<void> _exportAsCsv() async {
    if (_tableData.isEmpty) return;
    try {
      final appDir = await DocumentStorageService.instance.appDirectory;
      final file = File(
          '${appDir.path}/tabel_${DateTime.now().millisecondsSinceEpoch}.csv');
      final buffer = StringBuffer();

      for (final row in _tableData) {
        final escapedRow = row.map((cell) {
          final escaped = cell.replaceAll('"', '""');
          return '"$escaped"';
        }).join(',');
        buffer.writeln(escapedRow);
      }

      await file.writeAsString(buffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File CSV berhasil dibuat: ${file.path}')),
        );
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Hasil Ekstraksi Tabel Dokumen (.CSV)',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor CSV: $e')),
        );
      }
    }
  }

  void _copyAsTsv() {
    if (_tableData.isEmpty) return;
    final buffer = StringBuffer();
    for (final row in _tableData) {
      buffer.writeln(row.join('\t'));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Data tabel disalin (Format TSV siap paste di Excel/Google Sheets)')),
    );
  }

  void _editCell(int rowIndex, int colIndex) async {
    final currentVal = _tableData[rowIndex][colIndex];
    final ctrl = TextEditingController(text: currentVal);

    final newVal = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Sel [B${rowIndex + 1}, K${colIndex + 1}]'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newVal != null && mounted) {
      setState(() {
        _tableData[rowIndex][colIndex] = newVal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Ekstraksi Teks & Tabel (OCR)'),
        actions: [
          if (_displayMode == OcrDisplayMode.text &&
              _textCtrl.text.isNotEmpty) ...[
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
          ] else if (_displayMode == OcrDisplayMode.table &&
              _tableData.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'Salin Format Excel (TSV)',
              onPressed: _copyAsTsv,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: 'Ekspor ke Excel / CSV',
              onPressed: _exportAsCsv,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Image preview container or empty picker
          Container(
            height: 160,
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
                          label: const Text('Ganti',
                              style: TextStyle(fontSize: 12)),
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
                        const Text(
                            'Pilih foto dokumen untuk mengekstrak teks atau tabel',
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
                              onPressed: () =>
                                  _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: const Text('Galeri'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),

          // Mode Selector Switcher: [ Teks Biasa ] vs [ Mode Tabel / Excel ]
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<OcrDisplayMode>(
                    segments: const [
                      ButtonSegment(
                        value: OcrDisplayMode.text,
                        icon: Icon(Icons.description_outlined),
                        label: Text('Teks Biasa'),
                      ),
                      ButtonSegment(
                        value: OcrDisplayMode.table,
                        icon: Icon(Icons.grid_on),
                        label: Text('Tabel ke Excel'),
                      ),
                    ],
                    selected: {_displayMode},
                    onSelectionChanged: (val) {
                      setState(() => _displayMode = val.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Content Area (Text Editor OR Interactive Table Grid)
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
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
                          CircularProgressIndicator(
                              color: theme.colorScheme.primary),
                          const SizedBox(height: 12),
                          const Text('Memindai struktur teks & tabel...',
                              style: TextStyle(color: ArchTheme.textSecondary)),
                        ],
                      ),
                    )
                  : _displayMode == OcrDisplayMode.text
                      ? TextField(
                          controller: _textCtrl,
                          maxLines: null,
                          expands: true,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: isDark
                                ? ArchTheme.darkTextPrimary
                                : ArchTheme.lightTextPrimary,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Teks hasil OCR akan muncul di sini...',
                            border: InputBorder.none,
                          ),
                        )
                      : _buildTableView(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableView(ThemeData theme) {
    if (_tableData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_rows_outlined, size: 40, color: theme.dividerColor),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada struktur tabel atau kolom yang terdeteksi.',
              style: TextStyle(color: ArchTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Terdeteksi ${_tableData.length} baris, ${_tableData.first.length} kolom',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: ArchTheme.textSecondary),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _copyAsTsv,
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Salin Excel', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _exportAsCsv,
                  icon: const Icon(Icons.file_download, size: 14),
                  label: const Text('Ekspor .CSV', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
              ],
            ),
          ],
        ),
        const Divider(height: 16),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.all(
                  color: theme.dividerColor.withValues(alpha: 0.7),
                  width: 1,
                ),
                children: _tableData.asMap().entries.map((entry) {
                  final rowIdx = entry.key;
                  final row = entry.value;
                  final isHeader = rowIdx == 0;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isHeader
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : (rowIdx % 2 == 0
                              ? Colors.transparent
                              : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.2)),
                    ),
                    children: row.asMap().entries.map((cEntry) {
                      final colIdx = cEntry.key;
                      final cellText = cEntry.value;

                      return InkWell(
                        onTap: () => _editCell(rowIdx, colIdx),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Text(
                            cellText.isEmpty ? '-' : cellText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isHeader
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isHeader
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
