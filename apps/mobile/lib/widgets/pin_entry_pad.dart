import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable 6-digit PIN entry widget with an in-app numeric keypad.
/// Used for PIN setup (PGW-2) and payment confirmation (PGW-4+).
class PinEntryPad extends StatefulWidget {
  const PinEntryPad({
    super.key,
    required this.title,
    required this.onSubmit,
  });

  final String title;
  /// Called with the 6-digit PIN. Throw to show an error and clear the pad.
  final Future<void> Function(String pin) onSubmit;

  @override
  State<PinEntryPad> createState() => _PinEntryPadState();
}

class _PinEntryPadState extends State<PinEntryPad> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  void _tap(String digit) {
    if (_busy) return;
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
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_pin);
    } catch (e) {
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      // Clear the whole PIN after an error — the API needs a full fresh PIN.
      setState(() {
        _error = msg;
        _pin = '';
        _busy = false;
      });
      HapticFeedback.heavyImpact();
      return;
    }
    // Success. The screen may already have been popped by onSubmit — only
    // reset state if we're still visible (e.g. two-phase PIN setup).
    if (mounted) {
      setState(() {
        _busy = false;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ),
        if (_busy)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: _Keypad(onTap: _tap)),
      ],
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
