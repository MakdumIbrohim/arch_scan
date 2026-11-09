import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef VersionC = Int32 Function();
typedef VersionDart = int Function();

typedef DetectCornersC = Int32 Function(Pointer<Utf8>, Pointer<Float>);
typedef DetectCornersDart = int Function(Pointer<Utf8>, Pointer<Float>);

typedef ProcessPageC = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Float>, Int32, Int32);
typedef ProcessPageDart = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Float>, int, int);

typedef GeneratePdfC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef GeneratePdfDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef GenerateSearchablePdfC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef GenerateSearchablePdfDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef GenerateConfiguredPdfC = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef GenerateConfiguredPdfDart = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef StitchIdCardC = Int32 Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef StitchIdCardDart = int Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef StitchLongImageC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef StitchLongImageDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

class Point2D {
  final double x;
  final double y;
  const Point2D(this.x, this.y);

  @override
  String toString() => 'Point2D($x, $y)';
}

enum ScanFilter {
  original(0, 'Original'),
  magicColor(1, 'Magic Color'),
  blackAndWhite(2, 'B&W'),
  grayscale(3, 'Grayscale'),
  sharp(4, 'Sharp');

  final int id;
  final String label;
  const ScanFilter(this.id, this.label);
}

class ArchScanBridge {
  static final ArchScanBridge instance = ArchScanBridge._();

  late final DynamicLibrary _lib;
  late final VersionDart _versionFn;
  late final DetectCornersDart _detectCornersFn;
  late final ProcessPageDart _processPageFn;
  late final GeneratePdfDart _generatePdfFn;
  late final GenerateSearchablePdfDart _generateSearchablePdfFn;
  late final GenerateConfiguredPdfDart _generateConfiguredPdfFn;
  late final StitchIdCardDart _stitchIdCardFn;
  late final StitchLongImageDart _stitchLongImageFn;
  bool _initialized = false;

  ArchScanBridge._() {
    _initLib();
  }

  void _initLib() {
    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libarch_scan_core.so');
      } else if (Platform.isLinux) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidates = [
          '$exeDir/lib/libarch_scan_core.so',
          '$exeDir/libarch_scan_core.so',
          '/home/makdumibrohim/Projects/Mobile-Dev/flutter-projects/arch_scan/build/linux/x64/debug/bundle/lib/libarch_scan_core.so',
          '/home/makdumibrohim/Projects/Mobile-Dev/flutter-projects/arch_scan/libarch_scan_core.so',
          '/home/makdumibrohim/Projects/Mobile-Dev/flutter-projects/arch_scan/rust/target/release/libarch_scan_core.so',
          './libarch_scan_core.so',
          'libarch_scan_core.so',
        ];
        DynamicLibrary? loaded;
        for (final p in candidates) {
          try {
            loaded = DynamicLibrary.open(p);
            break;
          } catch (_) {}
        }
        _lib = loaded ?? DynamicLibrary.process();
      } else {
        _lib = DynamicLibrary.process();
      }

      _versionFn = _lib.lookupFunction<VersionC, VersionDart>('arch_scan_version');
      _detectCornersFn = _lib
          .lookupFunction<DetectCornersC, DetectCornersDart>('arch_scan_detect_corners');
      _processPageFn = _lib
          .lookupFunction<ProcessPageC, ProcessPageDart>('arch_scan_process_page');
      _generatePdfFn = _lib
          .lookupFunction<GeneratePdfC, GeneratePdfDart>('arch_scan_generate_pdf');
      _generateSearchablePdfFn = _lib.lookupFunction<GenerateSearchablePdfC,
          GenerateSearchablePdfDart>('arch_scan_generate_searchable_pdf');
      _generateConfiguredPdfFn = _lib.lookupFunction<GenerateConfiguredPdfC,
          GenerateConfiguredPdfDart>('arch_scan_generate_pdf_configured');
      _stitchIdCardFn = _lib.lookupFunction<StitchIdCardC,
          StitchIdCardDart>('arch_scan_stitch_id_card');
      _stitchLongImageFn = _lib.lookupFunction<StitchLongImageC,
          StitchLongImageDart>('arch_scan_stitch_long_image');
      _initialized = true;
    } catch (e) {
      // ignore: avoid_print
      print('ArchScanBridge initialization error: $e');
      _initialized = false;
    }
  }

  bool get isReady => _initialized;

  int getVersion() {
    if (!_initialized) return 0;
    return _versionFn();
  }

  List<Point2D> detectCorners(String imagePath) {
    if (!_initialized) {
      return const [
        Point2D(0.05, 0.05),
        Point2D(0.95, 0.05),
        Point2D(0.95, 0.95),
        Point2D(0.05, 0.95),
      ];
    }

    final pathPtr = imagePath.toNativeUtf8();
    final pointsPtr = calloc<Float>(8);

    try {
      final res = _detectCornersFn(pathPtr, pointsPtr);
      if (res != 0) {
        return const [
          Point2D(0.05, 0.05),
          Point2D(0.95, 0.05),
          Point2D(0.95, 0.95),
          Point2D(0.05, 0.95),
        ];
      }

      return [
        Point2D(pointsPtr[0], pointsPtr[1]),
        Point2D(pointsPtr[2], pointsPtr[3]),
        Point2D(pointsPtr[4], pointsPtr[5]),
        Point2D(pointsPtr[6], pointsPtr[7]),
      ];
    } finally {
      calloc.free(pathPtr);
      calloc.free(pointsPtr);
    }
  }

  bool processPage({
    required String inputPath,
    required String outputPath,
    required List<Point2D> corners,
    required ScanFilter filter,
    required int rotationDegrees,
  }) {
    if (!_initialized) return false;

    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    final pointsPtr = calloc<Float>(8);

    try {
      pointsPtr[0] = corners[0].x;
      pointsPtr[1] = corners[0].y;
      pointsPtr[2] = corners[1].x;
      pointsPtr[3] = corners[1].y;
      pointsPtr[4] = corners[2].x;
      pointsPtr[5] = corners[2].y;
      pointsPtr[6] = corners[3].x;
      pointsPtr[7] = corners[3].y;

      final res = _processPageFn(
        inPtr,
        outPtr,
        pointsPtr,
        filter.id,
        rotationDegrees,
      );
      return res == 0;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
      calloc.free(pointsPtr);
    }
  }

  bool generatePdf({
    required List<String> imagePaths,
    required String outputPdfPath,
  }) {
    if (!_initialized) return false;

    final jsonStr = jsonEncode(imagePaths);
    final jsonPtr = jsonStr.toNativeUtf8();
    final outPtr = outputPdfPath.toNativeUtf8();

    try {
      final res = _generatePdfFn(jsonPtr, outPtr);
      return res == 0;
    } finally {
      calloc.free(jsonPtr);
      calloc.free(outPtr);
    }
  }

  bool generateSearchablePdf({
    required List<PageSpecData> pages,
    required String outputPdfPath,
  }) {
    if (!_initialized) return false;

    final jsonStr = jsonEncode(pages.map((p) => p.toJson()).toList());
    final jsonPtr = jsonStr.toNativeUtf8();
    final outPtr = outputPdfPath.toNativeUtf8();

    try {
      final res = _generateSearchablePdfFn(jsonPtr, outPtr);
      return res == 0;
    } catch (_) {
      // Fallback to standard PDF
      return generatePdf(
        imagePaths: pages.map((p) => p.imagePath).toList(),
        outputPdfPath: outputPdfPath,
      );
    } finally {
      calloc.free(jsonPtr);
      calloc.free(outPtr);
    }
  }

  bool generateConfiguredPdf({
    required List<PageSpecData> pages,
    required PdfSettings settings,
    required String outputPdfPath,
  }) {
    if (!_initialized) return false;

    final pagesJson = jsonEncode(pages.map((p) => p.toJson()).toList());
    final configJson = jsonEncode(settings.toJson());

    final pagesPtr = pagesJson.toNativeUtf8();
    final configPtr = configJson.toNativeUtf8();
    final outPtr = outputPdfPath.toNativeUtf8();

    try {
      final res = _generateConfiguredPdfFn(pagesPtr, configPtr, outPtr);
      return res == 0;
    } catch (_) {
      return generateSearchablePdf(
        pages: pages,
        outputPdfPath: outputPdfPath,
      );
    } finally {
      calloc.free(pagesPtr);
      calloc.free(configPtr);
      calloc.free(outPtr);
    }
  }

  bool stitchIdCard({
    required String frontPath,
    required String backPath,
    required String outputPath,
  }) {
    if (!_initialized) return false;

    final fPtr = frontPath.toNativeUtf8();
    final bPtr = backPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();

    try {
      final res = _stitchIdCardFn(fPtr, bPtr, outPtr);
      return res == 0;
    } finally {
      calloc.free(fPtr);
      calloc.free(bPtr);
      calloc.free(outPtr);
    }
  }

  bool stitchLongImage({
    required List<String> imagePaths,
    required String outputPath,
  }) {
    if (!_initialized) return false;

    final jsonStr = jsonEncode(imagePaths);
    final inPtr = jsonStr.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();

    try {
      final res = _stitchLongImageFn(inPtr, outPtr);
      return res == 0;
    } finally {
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }
}

enum PdfPaperSize {
  a4('A4', 'A4 (210 x 297 mm)'),
  letter('Letter', 'US Letter (8.5 x 11 in)'),
  fit('Fit', 'Fit to Image');

  final String code;
  final String label;
  const PdfPaperSize(this.code, this.label);
}

enum PdfQuality {
  high('High', 'High Quality (300 DPI)'),
  medium('Medium', 'Standard (Balanced)'),
  low('Low', 'Compact (Smallest Size)');

  final String code;
  final String label;
  const PdfQuality(this.code, this.label);
}

class PdfSettings {
  final PdfPaperSize paperSize;
  final PdfQuality quality;

  const PdfSettings({
    this.paperSize = PdfPaperSize.a4,
    this.quality = PdfQuality.high,
  });

  Map<String, dynamic> toJson() => {
        'paper_size': paperSize.code,
        'quality': quality.code,
      };
}

class OcrItem {
  final String text;
  final double x;
  final double y;
  final double fontSize;

  const OcrItem({
    required this.text,
    required this.x,
    required this.y,
    this.fontSize = 12.0,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'font_size': fontSize,
      };

  factory OcrItem.fromJson(Map<String, dynamic> json) => OcrItem(
        text: json['text'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        fontSize: (json['font_size'] as num?)?.toDouble() ?? 12.0,
      );
}

class PageSpecData {
  final String imagePath;
  final List<OcrItem> ocrItems;

  const PageSpecData({
    required this.imagePath,
    this.ocrItems = const [],
  });

  Map<String, dynamic> toJson() => {
        'image_path': imagePath,
        'ocr_items': ocrItems.map((e) => e.toJson()).toList(),
      };
}
