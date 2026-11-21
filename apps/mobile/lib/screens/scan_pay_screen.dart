import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/checkout_confirm_screen.dart';
import 'package:minipay/screens/success_screen.dart';
import 'package:minipay/screens/transfer_screen.dart';
import 'package:minipay/widgets/pin_entry_pad.dart';

/// Scans a merchant QR and takes the user through confirmation.
class ScanPayScreen extends StatefulWidget {
  const ScanPayScreen({super.key});

  @override
  State<ScanPayScreen> createState() => _ScanPayScreenState();
}

class _ScanPayScreenState extends State<ScanPayScreen> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme != 'minipay') {
        continue; // not ours — keep scanning
      }
      // Online checkout QR: minipay://checkout/<checkoutId>
      if (uri.host == 'checkout') {
        final checkoutId = uri.path.replaceFirst('/', '');
        if (checkoutId.isEmpty) continue;
        _controller.stop();
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => CheckoutConfirmScreen(checkoutId: checkoutId),
            ))
            .then((_) => _controller.start());
        return;
      }
      // Personal receive-money QR (PGW-28): minipay://user/<email>
      if (uri.host == 'user') {
        final email = uri.path.replaceFirst('/', '').trim();
        if (email.isEmpty) continue;
        _controller.stop();
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => TransferScreen(prefillEmail: email),
            ))
            .then((_) => _controller.start());
        return;
      }
      if (uri.host != 'pay') continue;
      final code = uri.queryParameters['merchant'];
      if (code == null || code.isEmpty) continue;
      // Stop the camera before navigating on.
      _controller.stop();
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => ConfirmPaymentScreen(merchantCode: code),
          ))
          .then((_) => _controller.start());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan to pay',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Viewfinder: dimmed surroundings + bordered scan window.
          CustomPaint(
            painter: _ViewfinderPainter(),
            child: const SizedBox.expand(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Point the camera at a MiniPay QR code (merchant or personal)',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a centered scan window with a border; the area outside is dimmed.
class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.72,
      height: size.width * 0.72,
    );
    final rrect = RRect.fromRectAndRadius(scanRect, const Radius.circular(20));

    // Dim everything outside the window.
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect);
    canvas.drawPath(dim, Paint()..color = Colors.black.withAlpha(115));

    // Border of the scan window.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ConfirmPaymentScreen extends StatefulWidget {
  const ConfirmPaymentScreen({super.key, required this.merchantCode});
  final String merchantCode;

  @override
  State<ConfirmPaymentScreen> createState() => _ConfirmPaymentScreenState();
}

class _ConfirmPaymentScreenState extends State<ConfirmPaymentScreen> {
  final _amount = TextEditingController();
  final _localAuth = LocalAuthentication();
  String _merchantName = '';
  bool _loadingInfo = true;
  final bool _paying = false;
  String? _error;
  bool _biometricAvailable = false;
  String? _localPin;

  @override
  void initState() {
    super.initState();
    _loadMerchant();
    _checkBiometric();
  }

  Future<void> _loadMerchant() async {
    try {
      final res = await ApiClient.instance.dio
          .get('/merchants/${widget.merchantCode}');
      if (!mounted) return;
      setState(() {
        _merchantName = res.data['name'] as String;
        _loadingInfo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiError(e).message;
        _loadingInfo = false;
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
    final v = double.tryParse(_amount.text.trim());
    final cents = v == null ? 0 : (v * 100).round();
    if (cents < 100 || cents > 500000) {
      throw Exception('Enter an amount between SGD 1.00 and 5,000.00');
    }
    try {
      await ApiClient.instance.dio.post('/payments/merchant/pay',
          data: {
            'merchantCode': widget.merchantCode,
            'amount': cents,
            'pin': pin,
          });
      if (!mounted) return;
      final dollars = cents ~/ 100;
      final rem = (cents % 100).toString().padLeft(2, '0');
      final nav = Navigator.of(context);
      // Return to home first, then show success on top — Done pops to home.
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: 'Payment successful',
          amountText: 'S\$$dollars.$rem',
          subtitleLines: ['To $_merchantName'],
        ),
      ));
    } catch (e) {
      throw Exception(apiError(e).message);
    }
  }

  /// Biometric-only path: the device check releases the locally stored PIN.
  Future<void> _payWithBiometrics() async {
    setState(() => _error = null);
    final ok = await _biometricAuth();
    if (!ok) return; // cancelled or failed — stay on screen
    final stored = _localPin ?? await ApiClient.instance.readLocalPin();
    if (stored == null) {
      // No local copy of the PIN yet — fall back to the PIN pad once.
      _openPinPad();
      return;
    }
    try {
      await _payWithPin(stored);
    } catch (_) {
      // Stored PIN rejected (e.g. changed elsewhere) — forget it, ask for PIN.
      await ApiClient.instance.clearLocalPin();
      if (!mounted) return;
      setState(() => _localPin = null);
      _openPinPad();
    }
  }

  void _openPinPad() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Confirm PIN')),
        body: SafeArea(
          child: PinEntryPad(
            title: 'Pay $_merchantName',
            onSubmit: _payWithPin,
          ),
        ),
      ),
    ));
  }

  void _startPinPayment() {
    final v = double.tryParse(_amount.text.trim());
    final cents = v == null ? 0 : (v * 100).round();
    if (cents < 100 || cents > 500000) {
      setState(() =>
          _error = 'Amount must be between SGD 1.00 and 5,000.00');
      return;
    }
    setState(() => _error = null);
    _openPinPad();
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm payment')),
      body: _loadingInfo
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.storefront, size: 56, color: purple),
                  const SizedBox(height: 8),
                  Text(_merchantName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(widget.merchantCode,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      prefixText: 'S\$  ',
                      prefixStyle: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: purple),
                      hintText: '0.00',
                      border: InputBorder.none,
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_paying)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    // Bio XOR PIN: fingerprint authorizes directly (using the
                    // device-stored PIN); otherwise enter the PIN manually.
                    if (_biometricAvailable && _localPin != null)
                      FilledButton.icon(
                        onPressed: _payWithBiometrics,
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90D9),
                            minimumSize: const Size.fromHeight(52)),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Pay with fingerprint'),
                      ),
                    if (_biometricAvailable && _localPin != null)
                      const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _startPinPayment,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: BorderSide(color: Colors.grey.shade400)),
                      child: Text(_biometricAvailable && _localPin != null
                          ? 'Use PIN instead'
                          : 'Pay with PIN'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _biometricAvailable && _localPin != null
                        ? 'Fingerprint pays instantly — no PIN needed.'
                        : 'Confirm with your 6-digit payment PIN.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
