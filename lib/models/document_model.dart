import '../core/bridge/arch_scan_bridge.dart';

class ScanPage {
  final String id;
  final String rawImagePath;
  String processedImagePath;
  List<Point2D> corners;
  ScanFilter filter;
  int rotationDegrees;

  ScanPage({
    required this.id,
    required this.rawImagePath,
    required this.processedImagePath,
    required this.corners,
    this.filter = ScanFilter.magicColor,
    this.rotationDegrees = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawImagePath': rawImagePath,
        'processedImagePath': processedImagePath,
        'corners': corners.map((p) => {'x': p.x, 'y': p.y}).toList(),
        'filter': filter.id,
        'rotationDegrees': rotationDegrees,
      };

  factory ScanPage.fromJson(Map<String, dynamic> json) => ScanPage(
        id: json['id'] as String,
        rawImagePath: json['rawImagePath'] as String,
        processedImagePath: json['processedImagePath'] as String,
        corners: (json['corners'] as List)
            .map((c) => Point2D((c['x'] as num).toDouble(), (c['y'] as num).toDouble()))
            .toList(),
        filter: ScanFilter.values.firstWhere(
          (f) => f.id == (json['filter'] as int? ?? 1),
          orElse: () => ScanFilter.magicColor,
        ),
        rotationDegrees: json['rotationDegrees'] as int? ?? 0,
      );
}

class ScanDocument {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ScanPage> pages;
  String? pdfPath;

  ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
    this.pdfPath,
  });

  int get pageCount => pages.length;

  String get thumbnailPath =>
      pages.isNotEmpty ? pages.first.processedImagePath : '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
        'pdfPath': pdfPath,
      };

  factory ScanDocument.fromJson(Map<String, dynamic> json) => ScanDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        pages: (json['pages'] as List)
            .map((p) => ScanPage.fromJson(p as Map<String, dynamic>))
            .toList(),
        pdfPath: json['pdfPath'] as String?,
      );
}
