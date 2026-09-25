import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/widgets/pin_entry_pad.dart';

/// Full-screen 6-digit PIN setup (enter twice to confirm).
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _firstPin = '';
  bool _confirming = false;

  Future<void> _onSubmit(String pin) async {
    if (!_confirming) {
      setState(() {
        _firstPin = pin;
        _confirming = true;
      });
      return;
    }
    if (pin != _firstPin) {
      setState(() => _confirming = false);
      throw Exception('PINs did not match. Start again.');
    }
    await ApiClient.instance.dio.post('/auth/pin', data: {'pin': pin});
    // Keep a device-local copy so biometrics alone can authorize payments.
    await ApiClient.instance.saveLocalPin(pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Payment PIN set 🎉')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment PIN')),
      body: SafeArea(
        child: PinEntryPad(
          title: _confirming ? 'Confirm your PIN' : 'Create a 6-digit PIN',
          onSubmit: _onSubmit,
        ),
      ),
    );
  }
}
