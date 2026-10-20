import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/auth_screens.dart';
import 'package:minipay/screens/home_screen.dart';
import 'package:minipay/screens/lock_screen.dart';

/// Decides login vs lock vs home:
///   no session            -> LoginScreen
///   session + app lock ON -> LockScreen (until unlocked this app-open)
///   session + app lock OFF-> HomeScreen
/// The lock is per app-open: every fresh start re-locks.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _hasSession = false;
  bool _lockEnabled = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final has = await ApiClient.instance.hasSession();
    final lock = has && await ApiClient.instance.readAppLockEnabled();
    setState(() {
      _hasSession = has;
      _lockEnabled = lock;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasSession) return const LoginScreen();
    if (_lockEnabled) {
      return LockScreen(
        onUnlocked: () => setState(() => _lockEnabled = false),
        onLogout: () => setState(() {
          _hasSession = false;
          _lockEnabled = false;
        }),
      );
    }
    return const HomeScreen();
  }
}
