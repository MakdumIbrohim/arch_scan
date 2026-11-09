import 'dart:io';
import 'package:flutter/material.dart';
import '../core/bridge/arch_scan_bridge.dart';

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
  // 0..3 = corners (TL, TR, BR, BL)
  // 4..7 = edges (Top, Right, Bottom, Left)
  int? _activeTargetIndex;
  Offset? _lastPanPos;

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
    double closestDist = 44.0; // Touch radius

    // 1. Check 4 corners
    for (int i = 0; i < 4; i++) {
      final pos = Offset(_corners[i].x * w, _corners[i].y * h);
      final dist = (pos - touch).distance;
      if (dist < closestDist) {
        closestDist = dist;
        closestIdx = i;
      }
    }

    // 2. Check 4 edge midpoints
    if (closestIdx == null) {
      final edgeMidpoints = [
        Offset((_corners[0].x + _corners[1].x) * 0.5 * w, (_corners[0].y + _corners[1].y) * 0.5 * h), // Top
        Offset((_corners[1].x + _corners[2].x) * 0.5 * w, (_corners[1].y + _corners[2].y) * 0.5 * h), // Right
        Offset((_corners[2].x + _corners[3].x) * 0.5 * w, (_corners[2].y + _corners[3].y) * 0.5 * h), // Bottom
        Offset((_corners[3].x + _corners[0].x) * 0.5 * w, (_corners[3].y + _corners[0].y) * 0.5 * h), // Left
      ];

      for (int i = 0; i < 4; i++) {
        final dist = (edgeMidpoints[i] - touch).distance;
        if (dist < closestDist) {
          closestDist = dist;
          closestIdx = 4 + i;
        }
      }
    }

    setState(() {
      _activeTargetIndex = closestIdx;
      _lastPanPos = touch;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (_activeTargetIndex == null || _lastPanPos == null) return;

    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final touch = details.localPosition;
    final dx = (touch.dx - _lastPanPos!.dx) / w;
    final dy = (touch.dy - _lastPanPos!.dy) / h;
    _lastPanPos = touch;

    final target = _activeTargetIndex!;

    if (target < 4) {
      // Single corner movement
      final nx = (_corners[target].x + dx).clamp(0.0, 1.0);
      final ny = (_corners[target].y + dy).clamp(0.0, 1.0);
      setState(() {
        _corners[target] = Point2D(nx, ny);
      });
    } else {
      // Edge midpoint moves both adjacent corners
      final edge = target - 4;
      final c1 = edge;
      final c2 = (edge + 1) % 4;

      setState(() {
        _corners[c1] = Point2D(
          (_corners[c1].x + dx).clamp(0.0, 1.0),
          (_corners[c1].y + dy).clamp(0.0, 1.0),
        );
        _corners[c2] = Point2D(
          (_corners[c2].x + dx).clamp(0.0, 1.0),
          (_corners[c2].y + dy).clamp(0.0, 1.0),
        );
      });
    }

    widget.onCornersChanged(_corners);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _activeTargetIndex = null;
      _lastPanPos = null;
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
                  activeTarget: _activeTargetIndex,
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
  final int? activeTarget;

  _CropOverlayPainter({required this.corners, this.activeTarget});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    final pts = corners.map((c) => Offset(c.x * size.width, c.y * size.height)).toList();

    // 1. Clean darkened overlay outside crop box
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final fullRect = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final quadPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    final diff = Path.combine(PathOperation.difference, fullRect, quadPath);
    canvas.drawPath(diff, bgPaint);

    // 2. Clean 1.5px solid white border lines
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(quadPath, linePaint);

    // 3. Draw 4 corner handles (circle with inner dot)
    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = const Color(0xFF18181B)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final p = pts[i];
      final isSel = (i == activeTarget);
      final r = isSel ? 12.0 : 8.0;

      canvas.drawCircle(p, r, handleFill);
      canvas.drawCircle(p, r, handleStroke);
    }

    // 4. Draw 4 edge midpoint handles (pill / small rectangle)
    final edgePaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (int i = 0; i < 4; i++) {
      final mid = Offset(
        (pts[i].dx + pts[(i + 1) % 4].dx) * 0.5,
        (pts[i].dy + pts[(i + 1) % 4].dy) * 0.5,
      );
      final isSel = (activeTarget == 4 + i);
      final r = isSel ? 6.0 : 4.5;

      canvas.drawCircle(mid, r, edgePaint);
      canvas.drawCircle(mid, r, handleStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => true;
}
