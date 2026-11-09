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
  bool _initialized = false;

  ArchScanBridge._() {
    _initLib();
  }

  void _initLib() {
    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libarch_scan_core.so');
      } else if (Platform.isLinux) {
        // Try local directories
        final candidates = [
          './libarch_scan_core.so',
          './rust/target/release/libarch_scan_core.so',
          '/home/makdumibrohim/Projects/Mobile-Dev/flutter-projects/arch_scan/libarch_scan_core.so',
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
}
