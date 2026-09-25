import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/auth_screens.dart';
import 'package:minipay/screens/home_screen.dart';

/// Decides login vs home based on whether we have a stored session.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final has = await ApiClient.instance.hasSession();
    setState(() {
      _hasSession = has;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _hasSession ? const HomeScreen() : const LoginScreen();
  }
}
