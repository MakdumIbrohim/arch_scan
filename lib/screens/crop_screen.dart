import 'package:flutter/material.dart';
import '../core/bridge/arch_scan_bridge.dart';
import '../core/theme/arch_theme.dart';
import '../widgets/interactive_crop_view.dart';
import 'filter_screen.dart';

class CropScreen extends StatefulWidget {
  final String imagePath;
  final String? documentId;
  final String? pageId;

  const CropScreen({
    super.key,
    required this.imagePath,
    this.documentId,
    this.pageId,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late List<Point2D> _corners;
  bool _isDetecting = true;

  @override
  void initState() {
    super.initState();
    _detectCorners();
  }

  void _detectCorners() {
    setState(() => _isDetecting = true);
    final detected = ArchScanBridge.instance.detectCorners(widget.imagePath);
    setState(() {
      _corners = detected;
      _isDetecting = false;
    });
  }

  void _resetToFull() {
    setState(() {
      _corners = const [
        Point2D(0.0, 0.0),
        Point2D(1.0, 0.0),
        Point2D(1.0, 1.0),
        Point2D(0.0, 1.0),
      ];
    });
  }

  void _proceedToFilter() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FilterScreen(
          rawImagePath: widget.imagePath,
          corners: _corners,
          documentId: widget.documentId,
          pageId: widget.pageId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Adjust Boundary'),
        actions: [
          TextButton.icon(
            onPressed: _resetToFull,
            icon: Icon(Icons.fullscreen, color: isDark ? Colors.white70 : const Color(0xFF475569), size: 20),
            label: Text('Full', style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF475569))),
          ),
          IconButton(
            onPressed: _detectCorners,
            icon: Icon(Icons.auto_fix_high, color: theme.colorScheme.primary),
            tooltip: 'Auto Detect',
          ),
        ],
      ),
      body: _isDetecting
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: InteractiveCropView(
                        imagePath: widget.imagePath,
                        initialCorners: _corners,
                        onCornersChanged: (updated) {
                          _corners = updated;
                        },
                      ),
                    ),
                  ),
                ),
                Container(
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Drag handles to align document corners',
                        style: TextStyle(
                          color: isDark ? ArchTheme.darkTextSecondary : ArchTheme.lightTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _proceedToFilter,
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
