import 'package:flutter/material.dart';

import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BottariApp());
}

class BottariApp extends StatelessWidget {
  const BottariApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '보따리 - AI 여행 준비 플래너',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF9F8F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006B3E),
          primary: const Color(0xFF006B3E),
          secondary: const Color(0xFF2E8B57),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF9F8F7),
          foregroundColor: Color(0xFF1C1C1E),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        // Flutter 3.24.5 호환을 위해 CardThemeData -> CardTheme으로 수정
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}
