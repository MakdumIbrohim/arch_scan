import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:arch_scan/core/bridge/arch_scan_bridge.dart';

void main() {
  test('End-to-End Flutter to Rust FFI pipeline test', () {
    final bridge = ArchScanBridge.instance;
    expect(bridge.isReady, isTrue);
    expect(bridge.getVersion(), 100);

    // 1. Create a synthetic test PPM / PNG image
    final testDir = Directory('.test_pipeline_tmp');
    if (!testDir.existsSync()) testDir.createSync(recursive: true);

    final rawPath = '${testDir.path}/raw_input.png';
    final procPath = '${testDir.path}/processed_output.jpg';
    final pdfPath = '${testDir.path}/document.pdf';

    // 100x100 white image with black box
    final f = File(rawPath);
    // Write minimal 100x100 PNG header & data or use PPM/BMP
    // Since rust image crate supports PNG/JPEG, let's write via python or test helper
    final py = Process.runSync('python3', [
      '-c',
      '''
import struct, zlib

def make_png(w, h, filename):
    raw_data = bytearray()
    for y in range(h):
        raw_data.append(0) # filter type none
        for x in range(w):
            if 20 <= x <= 80 and 20 <= y <= 80:
                raw_data.extend([240, 240, 240])
            else:
                raw_data.extend([40, 40, 40])
    
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    png = b"\\x89PNG\\r\\n\\x1a\\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw_data)))
    png += chunk(b"IEND", b"")
    with open(filename, "wb") as f:
        f.write(png)

make_png(120, 160, "$rawPath")
'''
    ]);
    expect(py.exitCode, 0);
    expect(f.existsSync(), isTrue);

    // 2. Corner detection
    final corners = bridge.detectCorners(rawPath);
    expect(corners.length, 4);

    // 3. Process page: perspective warp + Magic Color filter
    final okProc = bridge.processPage(
      inputPath: rawPath,
      outputPath: procPath,
      corners: corners,
      filter: ScanFilter.magicColor,
      rotationDegrees: 0,
    );
    expect(okProc, isTrue);
    expect(File(procPath).existsSync(), isTrue);

    // 4. Generate PDF
    final okPdf = bridge.generatePdf(
      imagePaths: [procPath],
      outputPdfPath: pdfPath,
    );
    expect(okPdf, isTrue);
    expect(File(pdfPath).existsSync(), isTrue);
    expect(File(pdfPath).lengthSync(), greaterThan(100));

    // Clean up
    testDir.deleteSync(recursive: true);
  });
}
