import 'package:flutter/material.dart';

void main() {
  runApp(const SpyApp());
}

class AppColors {
  static const background = Color(0xFF0B1020);
  static const primary = Color(0xFF8B5CF6);
  static const secondary = Color(0xFF22D3EE);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const text = Color(0xFFF8FAFC);
  static const card = Color(0xFF171F35);
}

class SpyApp extends StatelessWidget {
  const SpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IS EVERYONE SPY HERE?',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          error: AppColors.danger,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.45),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.visibility_off,
                      size: 64, color: AppColors.secondary),
                  SizedBox(height: 16),
                  Text(
                    'IS EVERYONE\nSPY HERE?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Phase 1 works!',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
