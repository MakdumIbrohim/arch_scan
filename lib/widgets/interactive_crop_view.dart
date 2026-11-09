import 'dart:io';
import 'package:flutter/material.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';

class InteractiveCropView extends StatefulWidget {
  final String imagePath;
  final List<Point2D> initialCorners;
  final ValueChanged<List<Point2D>> onCornersChanged;

  const InteractiveCropView({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    required this.onCornersChanged,
  });

  @override
  State<InteractiveCropView> createState() => _InteractiveCropViewState();
}

class _InteractiveCropViewState extends State<InteractiveCropView> {
  late List<Point2D> _corners;
  int? _activeCornerIndex;

  @override
  void initState() {
    super.initState();
    _corners = List.from(widget.initialCorners);
  }

  @override
  void didUpdateWidget(covariant InteractiveCropView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCorners != widget.initialCorners) {
      _corners = List.from(widget.initialCorners);
    }
  }

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    final touch = details.localPosition;
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;

    int? closestIdx;
    double closestDist = 50.0; // Touch radius

    for (int i = 0; i < _corners.length; i++) {
      final cornerPos = Offset(_corners[i].x * w, _corners[i].y * h);
      final dist = (cornerPos - touch).distance;
      if (dist < closestDist) {
        closestDist = dist;
        closestIdx = i;
      }
    }

    setState(() {
      _activeCornerIndex = closestIdx;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_activeCornerIndex == null) return;

    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final touch = details.localPosition;

    final nx = (touch.dx / w).clamp(0.0, 1.0);
    final ny = (touch.dy / h).clamp(0.0, 1.0);

    setState(() {
      _corners[_activeCornerIndex!] = Point2D(nx, ny);
    });

    widget.onCornersChanged(_corners);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _activeCornerIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (d) => _onPanStart(d, constraints),
          onPanUpdate: (d) => _onPanUpdate(d, constraints),
          onPanEnd: _onPanEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(widget.imagePath),
                fit: BoxFit.fill,
              ),
              CustomPaint(
                painter: _CropOverlayPainter(
                  corners: _corners,
                  activeIndex: _activeCornerIndex,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final List<Point2D> corners;
  final int? activeIndex;

  _CropOverlayPainter({required this.corners, this.activeIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    final points = corners.map((c) => Offset(c.x * size.width, c.y * size.height)).toList();

    // 1. Draw darkened overlay outside polygon
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final quadPath = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    final diffPath = Path.combine(PathOperation.difference, path, quadPath);
    canvas.drawPath(diffPath, bgPaint);

    // 2. Draw border lines
    final linePaint = Paint()
      ..color = ArchTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(quadPath, linePaint);

    // 3. Draw grid lines (rule of thirds inside quad)
    final gridPaint = Paint()
      ..color = ArchTheme.primary.withOpacity(0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (double t in [1.0 / 3.0, 2.0 / 3.0]) {
      final top = Offset.lerp(points[0], points[1], t)!;
      final bottom = Offset.lerp(points[3], points[2], t)!;
      canvas.drawLine(top, bottom, gridPaint);

      final left = Offset.lerp(points[0], points[3], t)!;
      final right = Offset.lerp(points[1], points[2], t)!;
      canvas.drawLine(left, right, gridPaint);
    }

    // 4. Draw corner handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = ArchTheme.primary
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isCurrent = (i == activeIndex);
      final radius = isCurrent ? 14.0 : 10.0;

      canvas.drawCircle(p, radius, handlePaint);
      canvas.drawCircle(p, radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => true;
}
