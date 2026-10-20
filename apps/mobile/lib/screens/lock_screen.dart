import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/widgets/pin_entry_pad.dart';

/// App lock (PGW-9). Shown after AuthGate confirms a session, before
/// HomeScreen, whenever the per-user app-lock preference is ON.
/// Every fresh app start re-locks — that is the point.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked, required this.onLogout});

  /// Called once the user is verified (biometric + stored PIN, or manual PIN).
  final VoidCallback onUnlocked;

  /// Called when the user chooses to abandon the session from the lock.
  final VoidCallback onLogout;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

enum _LockMode { checking, biometric, pin }

class _LockScreenState extends State<LockScreen> {
  final _localAuth = LocalAuthentication();
  _LockMode _mode = _LockMode.checking;
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Defensive: any local_auth failure means "no biometrics".
    bool bio = false;
    try {
      bio = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      bio = false;
    }
    if (!mounted) return;
    final storedPin = await ApiClient.instance.readLocalPin();
    setState(() {
      // Preference ON but no stored PIN (or biometrics unavailable):
      // fall back to the PIN pad directly.
      _mode = (bio && storedPin != null) ? _LockMode.biometric : _LockMode.pin;
    });
  }

  /// Fingerprint success -> confirm the locally stored PIN is still valid
  /// against the server, then unlock. If the stored PIN is rejected, clear
  /// it and drop to manual PIN entry.
  Future<void> _unlockWithBiometrics() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock MiniPay',
        biometricOnly: true,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _authenticating = false);
        return;
      }
      final pin = await ApiClient.instance.readLocalPin();
      if (!mounted) return;
      if (pin == null) {
        setState(() {
          _authenticating = false;
          _mode = _LockMode.pin;
        });
        return;
      }
      await ApiClient.instance.verifyPin(pin);
      widget.onUnlocked();
    } on ApiException {
      // Stored PIN no longer valid (or session dead): wipe it, ask manually.
      await ApiClient.instance.clearLocalPin();
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _mode = _LockMode.pin;
        _error = 'Fingerprint unlock is no longer valid. Enter your PIN.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _error = 'Could not verify. Please use your PIN.';
      });
    }
  }

  Future<void> _unlockWithPin(String pin) async {
    await ApiClient.instance.verifyPin(pin);
    if (!mounted) return;
    // Remember the PIN locally so biometric unlock works next time.
    await ApiClient.instance.saveLocalPin(pin);
    widget.onUnlocked();
  }

  Future<void> _logout() async {
    final client = ApiClient.instance;
    final refresh = await client.refreshToken;
    if (refresh != null) {
      try {
        await client.dio.post('/auth/logout', data: {'refreshToken': refresh});
      } catch (_) {}
    }
    await client.clearSession();
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _mode == _LockMode.checking
            ? const Center(child: CircularProgressIndicator())
            : _mode == _LockMode.pin
                ? _buildPinBody()
                : _buildBiometricBody(primary),
      ),
    );
  }

  Widget _buildPinBody() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline,
                size: 20, color: Color(0xFF0F4C81)),
            const SizedBox(width: 8),
            const Text('MiniPay',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16283C))),
            const SizedBox(width: 16),
            TextButton(onPressed: _logout, child: const Text('Logout')),
          ],
        ),
        Expanded(
          child: PinEntryPad(
            title: 'Enter your 6-digit PIN to unlock',
            onSubmit: _unlockWithPin,
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricBody(Color primary) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Color(0xFF0F4C81)),
            const SizedBox(height: 16),
            const Text('MiniPay',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16283C))),
            const SizedBox(height: 8),
            Text('Your wallet is locked',
                style: Theme.of(context).textTheme.bodyMedium),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 48),
            _authenticating
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: 132,
                    height: 132,
                    child: FilledButton(
                      onPressed: _unlockWithBiometrics,
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint, size: 48),
                          SizedBox(height: 4),
                          Text('Unlock',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _authenticating
                  ? null
                  : () => setState(() {
                        _error = null;
                        _mode = _LockMode.pin;
                      }),
              child: const Text('Use PIN instead'),
            ),
            TextButton(
              onPressed: _logout,
              child: const Text('Logout',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
