import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';

/// Withdraw to wallet (PGW-22): move business balance to the owner's
/// personal MiniPay wallet.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, required this.businessBalanceMinor, required this.businessName});
  final String businessBalanceMinor;
  final String businessName;

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _amountCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int get _balanceCents => int.tryParse(widget.businessBalanceMinor) ?? 0;

  String _fmt(int cents) {
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    return '\$$dollars.$rem';
  }

  Future<void> _submit() async {
    final value = double.tryParse(_amountCtrl.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    final cents = (value * 100).round();
    if (cents > _balanceCents) {
      setState(() => _error =
          'Amount exceeds your business balance (${_fmt(_balanceCents)})');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio
          .post('/merchants/mine/withdraw', data: {'amountMinor': cents});
      if (!mounted) return;
      final wallet = res.data['walletBalanceMinor'] as String;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Withdrawn'),
          content: Text(
              '${_fmt(cents)} moved to your personal wallet.\n'
              'Wallet balance: ${_fmt(int.tryParse(wallet) ?? 0)}'),
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).popUntil((r) => r.isFirst),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map &&
              (e.response!.data as Map)['message'] != null
          ? (e.response!.data as Map)['message'].toString()
          : 'Withdrawal failed';
      setState(() => _error = msg);
    } catch (_) {
      if (mounted) setState(() => _error = 'Withdrawal failed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Withdraw to wallet')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F4C81),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.businessName} balance',
                      style: TextStyle(color: Colors.white.withAlpha(179))),
                  const SizedBox(height: 4),
                  Text(_fmt(_balanceCents),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Amount to withdraw (SGD)',
                        hintText: 'e.g. 25.00',
                        prefixText: 'S\$ ',
                        border: const OutlineInputBorder(),
                        suffixIcon: TextButton(
                          onPressed: () {
                            _amountCtrl.text =
                                (_balanceCents / 100).toStringAsFixed(2);
                          },
                          child: const Text('MAX'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        'Money moves instantly to your personal MiniPay '
                        'wallet.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  minimumSize: const Size.fromHeight(52)),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.account_balance),
              label:
                  Text(_submitting ? 'Withdrawing…' : 'Withdraw to wallet'),
            ),
          ],
        ),
      ),
    );
  }
}
