import 'package:flutter/material.dart';
import 'package:minipay/screens/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MiniPayApp());
}

class MiniPayApp extends StatelessWidget {
  const MiniPayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiniPay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C4DF6)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
