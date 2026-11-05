import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Collect payment (PGW-19): merchant enters an amount + optional note,
/// the app creates a checkout session and shows the QR for the customer
/// to scan and pay in the MiniPay app.
class CollectPaymentScreen extends StatefulWidget {
  const CollectPaymentScreen({super.key});

  @override
  State<CollectPaymentScreen> createState() => _CollectPaymentScreenState();
}

class _CollectResult {
  final String checkoutId;
  final String orderRef;
  final int amountMinor;
  final String qrPayload;
  final DateTime expiresAt;
  _CollectResult({
    required this.checkoutId,
    required this.orderRef,
    required this.amountMinor,
    required this.qrPayload,
    required this.expiresAt,
  });
}

class _CollectPaymentScreenState extends State<CollectPaymentScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _creating = false;
  String? _error;
  _CollectResult? _result;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final text = _amountCtrl.text.trim();
    final value = double.tryParse(text);
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    final cents = (value * 100).round();
    if (cents < 1 || cents > 5000000) {
      setState(() => _error = 'Amount must be between S\$0.01 and S\$50,000');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio.post('/merchants/mine/collect', data: {
        'amountMinor': cents,
        if (_noteCtrl.text.trim().isNotEmpty) 'description': _noteCtrl.text.trim(),
      });
      setState(() {
        _result = _CollectResult(
          checkoutId: res.data['checkoutId'] as String,
          orderRef: res.data['orderRef'] as String,
          amountMinor: int.parse(res.data['amountMinor'] as String),
          qrPayload: res.data['qrPayload'] as String,
          expiresAt: DateTime.parse(res.data['expiresAt'] as String).toLocal(),
        );
      });
    } on DioException catch (e) {
      final msg = e.response?.data is Map &&
              (e.response!.data as Map)['message'] != null
          ? (e.response!.data as Map)['message'].toString()
          : 'Could not create the payment request';
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Could not create the payment request');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _fmt(int cents) {
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    return '\$$dollars.$rem';
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Collect payment')),
      body: SafeArea(
        top: false,
        child: _result == null ? _buildForm(purple) : _buildQr(context),
      ),
    );
  }

  Widget _buildForm(Color purple) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Amount (SGD)',
                    hintText: 'e.g. 12.50',
                    prefixText: 'S\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteCtrl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  maxLength: 280,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. 2x kopi-o, 1x toast',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _creating ? null : _create,
          style: FilledButton.styleFrom(
              backgroundColor: purple, minimumSize: const Size.fromHeight(52)),
          icon: _creating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.qr_code_2),
          label: Text(_creating ? 'Creating…' : 'Show payment QR'),
        ),
        const SizedBox(height: 12),
        const Text(
          'The customer scans this QR with their MiniPay app and pays with '
          'their fingerprint or PIN. The request expires after 15 minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildQr(BuildContext context) {
    final r = _result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(_fmt(r.amountMinor),
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F4C81))),
                if (_noteCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_noteCtrl.text.trim(),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: QrImageView(
                    data: r.qrPayload,
                    size: 230,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Scan with MiniPay to pay',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Ref ${r.orderRef} · expires '
                    '${r.expiresAt.hour.toString().padLeft(2, '0')}:'
                    '${r.expiresAt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.check),
          label: const Text('Done'),
        ),
        TextButton(
          onPressed: () => setState(() => _result = null),
          child: const Text('Create another'),
        ),
      ],
    );
  }
}
