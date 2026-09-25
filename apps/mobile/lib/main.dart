import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minipay/screens/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw edge-to-edge; SafeArea/Scaffold handle the system nav bar insets.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.white,
  ));
  runApp(const MiniPayApp());
}

/// MiniPay professional palette:
///  - primary: deep classic blue (trust, finance)
///  - surface: near-white
///  - success: brand green for pay actions
class MiniPayApp extends StatelessWidget {
  const MiniPayApp({super.key});

  static const Color brandPrimary = Color(0xFF0F4C81);
  static const Color brandSuccess = Color(0xFF0FA958);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandPrimary,
      primary: brandPrimary,
    );
    return MaterialApp(
      title: 'MiniPay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF16283C),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF16283C),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: brandPrimary,
            foregroundColor: Colors.white,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
