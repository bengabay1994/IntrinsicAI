import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared/theme/app_theme.dart';
import 'features/home/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: IntrinsicAIApp()));
}

/// Root application widget.
class IntrinsicAIApp extends StatelessWidget {
  const IntrinsicAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IntrinsicAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
