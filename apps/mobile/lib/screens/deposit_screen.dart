import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';

class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

enum _DepositPhase { amount, paying, done }

class _DepositScreenState extends State<DepositScreen> {
  final _amount = TextEditingController();
  _DepositPhase _phase = _DepositPhase.amount;
  String? _error;
  String? _resultMessage;
  bool _resultSuccess = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _startDeposit(String card) async {
    final cents = _parseAmount(_amount.text);
    if (cents == null) {
      setState(() => _error = 'Enter an amount between SGD 1.00 and 5,000.00');
      return;
    }
    setState(() {
      _phase = _DepositPhase.paying;
      _error = null;
    });
    try {
      final dep = await ApiClient.instance.dio
          .post('/wallet/deposits', data: {'amount': cents});
      final txId = dep.data['transactionId'] as String;
      // "Pay" with the chosen Stripe test card (server confirms the intent).
      await ApiClient.instance.dio.post('/wallet/deposits/$txId/confirm-test',
          data: {'card': card});
      // Poll for the webhook credit.
      String status = 'PENDING';
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final st = await ApiClient.instance.dio.get('/wallet/transactions/$txId');
        status = st.data['status'] as String;
        if (status != 'PENDING') break;
      }
      if (!mounted) return;
      setState(() {
        _phase = _DepositPhase.done;
        _resultSuccess = status == 'COMPLETED';
        _resultMessage = _resultSuccess
            ? 'Deposit successful! Your wallet has been credited.'
            : status == 'FAILED'
                ? 'Payment was declined. Try another card.'
                : 'Still processing — check your balance in a moment.';
      });
    } catch (e) {
      setState(() {
        _phase = _DepositPhase.amount;
        _error = apiError(e).message;
      });
    }
  }

  int? _parseAmount(String text) {
    final v = double.tryParse(text.trim());
    if (v == null) return null;
    final cents = (v * 100).round();
    if (cents < 100 || cents > 500000) return null;
    return cents;
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Deposit money')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _phase == _DepositPhase.done
              ? _buildDone(context)
              : _buildForm(purple),
        ),
      ),
    );
  }

  Widget _buildForm(Color purple) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _amount,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixText: 'S\$  ',
            prefixStyle: TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: purple),
            hintText: '0.00',
            border: InputBorder.none,
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        Text('Min S\$1.00 · Max S\$5,000.00',
            style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        if (_phase == _DepositPhase.paying)
          const Column(children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Contacting Stripe…'),
          ])
        else ...[
          const Text('Pay with a test card',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _TestCardButton(
            label: 'Visa ······4242',
            asset: 'VISA',
            onTap: () => _startDeposit('visa'),
          ),
          const SizedBox(height: 8),
          _TestCardButton(
            label: 'Visa Debit ······4917',
            asset: 'VISA',
            onTap: () => _startDeposit('visa_debit'),
          ),
          const SizedBox(height: 8),
          _TestCardButton(
            label: 'Mastercard ······4444',
            asset: 'MC',
            onTap: () => _startDeposit('mastercard'),
          ),
          const SizedBox(height: 8),
          Text(
            'Test mode: these are Stripe test cards. No real money moves.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _resultSuccess ? Icons.check_circle : Icons.info_outline,
          size: 80,
          color: _resultSuccess ? Colors.green : Colors.orange,
        ),
        const SizedBox(height: 16),
        Text(
          _resultMessage ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              minimumSize: const Size.fromHeight(52)),
          child: const Text('Back to wallet'),
        ),
      ],
    );
  }
}

class _TestCardButton extends StatelessWidget {
  const _TestCardButton(
      {required this.label, required this.asset, required this.onTap});
  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: asset == 'VISA' ? const Color(0xFF1A1F71) : const Color(0xFFEB001B),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(asset,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
      label: Text(label),
    );
  }
}
