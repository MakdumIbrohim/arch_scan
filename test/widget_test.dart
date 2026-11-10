import 'package:flutter_test/flutter_test.dart';
import 'package:arch_scan/core/bridge/arch_scan_bridge.dart';
import 'package:arch_scan/main.dart';
import 'package:arch_scan/models/document_model.dart';

void main() {
  test('ArchScanBridge version check', () {
    final version = ArchScanBridge.instance.getVersion();
    // In test environment, version is 100 if native lib is loaded
    expect(version, anyOf(0, 100));
  });

  test('Document model serialization', () {
    final now = DateTime.now();
    final page = ScanPage(
      id: 'p1',
      rawImagePath: '/tmp/raw.jpg',
      processedImagePath: '/tmp/proc.jpg',
      corners: const [Point2D(0.1, 0.1), Point2D(0.9, 0.1), Point2D(0.9, 0.9), Point2D(0.1, 0.9)],
      filter: ScanFilter.magicColor,
      rotationDegrees: 90,
    );
    final doc = ScanDocument(
      id: 'doc1',
      title: 'Invoice Test',
      createdAt: now,
      updatedAt: now,
      pages: [page],
    );

    final json = doc.toJson();
    final restored = ScanDocument.fromJson(json);

    expect(restored.id, 'doc1');
    expect(restored.title, 'Invoice Test');
    expect(restored.pages.length, 1);
    expect(restored.pages.first.filter, ScanFilter.magicColor);
    expect(restored.pages.first.rotationDegrees, 90);
  });

  testWidgets('ArchScan UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ArchScanApp());
    await tester.pump();

    expect(find.text('ArchScan'), findsOneWidget);
  });
}
