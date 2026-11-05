import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/deposit_screen.dart';
import 'package:minipay/screens/success_screen.dart';
import 'package:minipay/widgets/pin_entry_pad.dart';

/// Confirms and pays an online checkout created by a merchant website,
/// scanned from a `minipay://checkout/<checkoutId>` QR code.
class CheckoutConfirmScreen extends StatefulWidget {
  const CheckoutConfirmScreen({super.key, required this.checkoutId});
  final String checkoutId;

  @override
  State<CheckoutConfirmScreen> createState() => _CheckoutConfirmScreenState();
}

class _CheckoutConfirmScreenState extends State<CheckoutConfirmScreen> {
  final _localAuth = LocalAuthentication();

  String? _merchantName;
  int? _amountMinor;
  String? _description;
  DateTime? _expiresAt;
  String? _status;

  bool _loading = true;
  final bool _paying = false;
  String? _error;
  bool _biometricAvailable = false;
  String? _localPin;

  @override
  void initState() {
    super.initState();
    _loadCheckout();
    _checkBiometric();
  }

  Future<void> _loadCheckout() async {
    try {
      final res = await ApiClient.instance.dio.get('/checkout/${widget.checkoutId}');
      if (!mounted) return;
      final data = res.data as Map;
      final expiresRaw = data['expiresAt'] as String?;
      setState(() {
        _merchantName = data['merchantName'] as String?;
        _amountMinor = int.tryParse(data['amountMinor']?.toString() ?? '');
        _description = data['description'] as String?;
        _expiresAt = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
        _status = data['status'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = apiError(e).message;
      setState(() {
        _error = msg;
        _status = null;
        _loading = false;
      });
    }
  }

  Future<void> _checkBiometric() async {
    final stored = await ApiClient.instance.readLocalPin();
    try {
      final can = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (!mounted) return;
      setState(() {
        _biometricAvailable = can && supported;
        _localPin = stored;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _localPin = stored);
    }
  }

  String get _amountText {
    final minor = _amountMinor ?? 0;
    final dollars = minor ~/ 100;
    final cents = (minor % 100).toString().padLeft(2, '0');
    return 'S\$$dollars.$cents';
  }

  Future<bool> _biometricAuth() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirm your payment',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Called by the PIN pad after 6 digits. Throws on failure.
  Future<void> _payWithPin(String pin) async {
    try {
      await ApiClient.instance.dio
          .post('/checkout/${widget.checkoutId}/pay', data: {'pin': pin});
      if (!mounted) return;
      final nav = Navigator.of(context);
      // Return to home first, then show success on top â€” Done pops to home.
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: 'Payment successful',
          amountText: _amountText,
          subtitleLines: ['To ${_merchantName ?? 'merchant'}'],
        ),
      ));
    } catch (e) {
      final msg = apiError(e).message;
      if (msg.toLowerCase().contains('insufficient funds')) {
        await _handleInsufficientFunds();
      }
      throw Exception(msg);
    }
  }

  Future<void> _handleInsufficientFunds() async {
    if (!mounted) return;
    final topUp = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not enough balance'),
        content: const Text(
            'Your wallet balance is too low for this payment.\nTop up now?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Later')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Top up')),
        ],
      ),
    );
    if (topUp == true && mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const DepositScreen()));
    }
  }

  /// Biometric-only path: the device check releases the locally stored PIN.
  Future<void> _payWithBiometrics() async {
    setState(() => _error = null);
    final ok = await _biometricAuth();
    if (!ok) return; // cancelled or failed â€” stay on screen
    final stored = _localPin ?? await ApiClient.instance.readLocalPin();
    if (stored == null) {
      _openPinPad();
      return;
    }
    try {
      await _payWithPin(stored);
    } catch (_) {
      // Stored PIN rejected (e.g. changed elsewhere) â€” forget it, ask for PIN.
      await ApiClient.instance.clearLocalPin();
      if (!mounted) return;
      setState(() => _localPin = null);
      _openPinPad();
    }
  }

  void _openPinPad() {
    setState(() => _error = null);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Confirm PIN')),
        body: SafeArea(
          child: PinEntryPad(
            title: 'Pay ${_merchantName ?? 'merchant'}',
            onSubmit: _payWithPin,
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm checkout')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: _buildBody(context, purple),
            ),
    );
  }

  Widget _buildBody(BuildContext context, Color purple) {
    // Unknown checkout / network failure during load.
    if (_status == null) {
      return _StatusView(
        icon: Icons.help_outline,
        color: Colors.red.shade400,
        title: 'Unknown checkout',
        message: _error ?? 'This checkout link is not valid.',
      );
    }
    switch (_status) {
      case 'PAID':
        return const _StatusView(
          icon: Icons.check_circle_outline,
          color: Color(0xFF1B7F4B),
          title: 'Already paid',
          message: 'This checkout has already been paid.',
        );
      case 'EXPIRED':
        return const _StatusView(
          icon: Icons.hourglass_disabled,
          color: Colors.orange,
          title: 'This checkout has expired',
          message: 'Ask the merchant for a new checkout link.',
        );
      case 'PENDING':
        return _buildPending(context, purple);
      default:
        return _StatusView(
          icon: Icons.error_outline,
          color: Colors.red.shade400,
          title: 'Unknown checkout',
          message: _error ?? 'Unexpected checkout status.',
        );
    }
  }

  Widget _buildPending(BuildContext context, Color purple) {
    final canBiometric = _biometricAvailable && _localPin != null;
    final expiresAt = _expiresAt;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.shopping_cart_checkout, size: 56, color: purple),
          const SizedBox(height: 8),
          Text(_merchantName ?? 'Merchant',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (_description != null && _description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_description!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: 24),
          Text(_amountText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827))),
          if (expiresAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Expires at '
                '${expiresAt.hour.toString().padLeft(2, '0')}:'
                '${expiresAt.minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 32),
          if (_paying)
            const Center(child: CircularProgressIndicator())
          else ...[
            // Bio XOR PIN: fingerprint authorizes directly (using the
            // device-stored PIN); otherwise enter the PIN manually.
            if (canBiometric)
              FilledButton.icon(
                onPressed: _payWithBiometrics,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90D9),
                    minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.fingerprint),
                label: const Text('Pay with fingerprint'),
              ),
            if (canBiometric) const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _openPinPad,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: Colors.grey.shade400)),
              child: Text(canBiometric ? 'Use PIN instead' : 'Pay with PIN'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          Text(
            canBiometric
                ? 'Fingerprint pays instantly â€” no PIN needed.'
                : 'Confirm with your 6-digit payment PIN.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Full-body state page for non-payable or failed checkouts.
class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
