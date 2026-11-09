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
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'ArchScan',
          debugShowCheckedModeBanner: false,
          theme: ArchTheme.lightTheme,
          darkTheme: ArchTheme.darkTheme,
          themeMode: ThemeService.instance.themeMode,
          home: const HomeScreen(),
        );
      },
    );
  }
}
