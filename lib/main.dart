import 'package:flutter/material.dart';
import 'core/theme/arch_theme.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArchScanApp());
}

class ArchScanApp extends StatelessWidget {
  const ArchScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ArchScan',
      debugShowCheckedModeBanner: false,
      theme: ArchTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
