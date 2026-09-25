import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minipay/api/api_client.dart';

/// Full-screen 6-digit PIN entry with a numeric keypad (no OS keyboard —
/// like real wallet apps; ready for biometric in PGW-4).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _firstPin = '';
  String _pin = '';
  bool _confirming = false;
  bool _saving = false;
  String? _error;

  void _tap(String digit) {
    if (_saving) return;
    if (digit == '<') {
      setState(() {
        _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1);
        _error = null;
      });
      return;
    }
    if (_pin.length >= 6) return;
    setState(() => _pin += digit);
    if (_pin.length == 6) _submit();
  }

  Future<void> _submit() async {
    if (!_confirming) {
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _firstPin) {
      setState(() {
        _pin = '';
        _confirming = false;
        _error = 'PINs did not match. Start again.';
      });
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.dio.post('/auth/pin', data: {'pin': _pin});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Payment PIN set 🎉')));
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = apiError(e).message;
        _pin = '';
        _confirming = false;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _confirming ? 'Confirm your PIN' : 'Create a 6-digit PIN';
    return Scaffold(
      appBar: AppBar(title: const Text('Payment PIN')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(shown, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? const Color(0xFF6C4DF6) : Colors.grey.shade300,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: _Keypad(onTap: _tap),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '<'],
    ];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((k) {
              if (k.isEmpty) return const SizedBox(width: 72, height: 56);
              return _Key(
                label: k,
                onTap: () => onTap(k),
                icon: k == '<' ? Icons.backspace_outlined : null,
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 56,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: icon != null
            ? Icon(icon)
            : Text(label, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
