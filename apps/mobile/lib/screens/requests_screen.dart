import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/deposit_screen.dart';
import 'package:minipay/widgets/pin_entry_pad.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestItem {
  final String id;
  final int amountMinor;
  final String status;
  final String counterparty;
  final String? note;
  final String direction; // IN = I owe, OUT = they owe me
  _RequestItem.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        amountMinor = int.tryParse(j['amount'] as String) ?? 0,
        status = j['status'] as String,
        counterparty = j['counterparty'] as String,
        note = j['note'] as String?,
        direction = j['direction'] as String;
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<_RequestItem> _toMe = [];
  List<_RequestItem> _fromMe = [];
  bool _loading = true;
  final _localAuth = LocalAuthentication();
  bool _biometricAvailable = false;
  String? _localPin;

  @override
  void initState() {
    super.initState();
    _load();
    _checkBiometric();
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

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/requests');
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _toMe = (data['toMe'] as List)
            .map((j) => _RequestItem.fromJson(j as Map<String, dynamic>))
            .toList();
        _fromMe = (data['fromMe'] as List)
            .map((j) => _RequestItem.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _createRequest() async {
    final email = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Request money',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'From (their email)',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (SGD)',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 140,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    final cents =
        ((double.tryParse(amount.text.trim()) ?? 0) * 100).round();
    try {
      await ApiClient.instance.dio.post('/requests', data: {
        'toEmail': email.text.trim(),
        'amount': cents,
        'note': note.text.trim().isEmpty ? null : note.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent 🎉')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          backgroundColor: Colors.red.shade300,
          behavior: SnackBarBehavior.floating));
    }
  }

  void _pay(_RequestItem r) {
    final bioReady = _biometricAvailable && _localPin != null;
    // Pay options: fingerprint directly, or the PIN pad — never both.
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pay ${_money(r.amountMinor)} to ${r.counterparty}',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (bioReady)
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _payWithBiometrics(r);
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90D9),
                      minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Pay with fingerprint'),
                ),
              if (bioReady) const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openPinPad(r);
                },
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: BorderSide(color: Colors.grey.shade400)),
                child: Text(bioReady ? 'Use PIN instead' : 'Pay with PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _payWithBiometrics(_RequestItem r) async {
    final ok = await _biometricAuth();
    if (!ok) return;
    final stored = _localPin ?? await ApiClient.instance.readLocalPin();
    if (stored == null) {
      _openPinPad(r);
      return;
    }
    try {
      await _payWithPin(r, stored);
    } catch (_) {
      await ApiClient.instance.clearLocalPin();
      if (!mounted) return;
      setState(() => _localPin = null);
      _openPinPad(r);
    }
  }

  void _openPinPad(_RequestItem r) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Confirm PIN')),
        body: SafeArea(
          child: PinEntryPad(
            title: 'Pay ${_money(r.amountMinor)} to ${r.counterparty}',
            onSubmit: (pin) => _payWithPin(r, pin),
          ),
        ),
      ),
    ));
  }

  Future<void> _payWithPin(_RequestItem r, String pin) async {
    try {
      await ApiClient.instance.dio
          .post('/requests/${r.id}/pay', data: {'pin': pin});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Paid ${_money(r.amountMinor)} to ${r.counterparty} 🎉')));
      Navigator.of(context).popUntil((route) => route.isFirst);
      _load();
    } catch (e) {
      final msg = apiError(e).message;
      // Offer a top-up when the wallet can't cover the request.
      if (msg.toLowerCase().contains('insufficient funds')) {
        await _handleInsufficientFunds();
      }
      // Friendly message for the PIN pad — never the raw DioException.
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
            'Your wallet balance is too low for this request.\nTop up now?'),
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
      _load();
    }
  }

  Future<void> _decline(_RequestItem r) async {
    try {
      await ApiClient.instance.dio.post('/requests/${r.id}/decline');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _cancel(_RequestItem r) async {
    try {
      await ApiClient.instance.dio.post('/requests/${r.id}/cancel');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          behavior: SnackBarBehavior.floating));
    }
  }

  String _money(int cents) {
    final d = cents ~/ 100;
    final r = (cents % 100).toString().padLeft(2, '0');
    return 'S\$$d.$r';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Requests'),
          bottom: const TabBar(
            tabs: [Tab(text: 'To me'), Tab(text: 'From me')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createRequest,
          icon: const Icon(Icons.request_quote),
          label: const Text('Request'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildList(_toMe, incoming: true),
                  _buildList(_fromMe, incoming: false),
                ],
              ),
      ),
    );
  }

  Widget _buildList(List<_RequestItem> items, {required bool incoming}) {
    if (items.isEmpty) {
      return const Center(
          child: Text('Nothing here.',
              style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final r = items[i];
          final pending = r.status == 'PENDING';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        incoming
                            ? '${r.counterparty} asked you'
                            : 'You asked ${r.counterparty}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        _money(r.amountMinor),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: pending
                                ? Theme.of(ctx).colorScheme.primary
                                : Colors.grey),
                      ),
                    ],
                  ),
                  if (r.note != null && r.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(r.note!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                  Text('Status: ${r.status}',
                      style: TextStyle(
                          fontSize: 12,
                          color: pending ? Colors.orange : Colors.grey)),
                  if (pending && incoming) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _pay(r),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Pay'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _decline(r),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Decline'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (pending && !incoming)
                    TextButton(
                      onPressed: () => _cancel(r),
                      child: const Text('Cancel request'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
