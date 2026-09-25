import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/bootstrap.dart';
import 'package:minipay/screens/deposit_screen.dart';
import 'package:minipay/screens/pin_setup.dart';
import 'package:minipay/screens/scan_pay_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _WalletData {
  String balanceMinor = '0';
  List<Map<String, dynamic>> recent = [];
  bool hasPin = false;
}

class _HomeScreenState extends State<HomeScreen> {
  final _data = _WalletData();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final walletRes = await ApiClient.instance.dio.get('/wallet');
      _data.balanceMinor = walletRes.data['balance'] as String;
      _data.recent =
          (walletRes.data['recent'] as List).cast<Map<String, dynamic>>();
      try {
        final pinRes = await ApiClient.instance.dio.get('/auth/pin/status');
        _data.hasPin = pinRes.data['hasPin'] as bool;
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
      }
      setState(() => _loading = false);
    } catch (e) {
      // Session is truly dead — go back to login.
      await ApiClient.instance.clearSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
    }
  }

  String get _balanceText {
    final cents = int.tryParse(_data.balanceMinor) ?? 0;
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    final sign = cents < 0 ? '-' : '';
    return '$sign\$$dollars.$rem';
  }

  Future<void> _logout() async {
    final refresh = await ApiClient.instance.refreshToken;
    if (refresh != null) {
      try {
        await Dio(BaseOptions(baseUrl: ApiClient.baseUrl))
            .post('/auth/logout', data: {'refreshToken': refresh});
      } catch (_) {}
    }
    await ApiClient.instance.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('MiniPay'),
        actions: [
          IconButton(
            icon: Icon(
              _data.hasPin ? Icons.verified_user : Icons.gpp_maybe_outlined,
              color: const Color(0xFF0F4C81),
            ),
            tooltip: _data.hasPin ? 'Payment PIN is set' : 'Set up payment PIN',
            onPressed: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PinSetupScreen()));
              _load();
            },
          ),
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Balance card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4C81),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet balance',
                        style: TextStyle(
                            color: Colors.white.withAlpha(179))),
                    const SizedBox(height: 6),
                    Text(_balanceText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('SGD · Singapore Dollar',
                        style: TextStyle(
                            color: Colors.white.withAlpha(153),
                            fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // Actions
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const DepositScreen()));
                      _load();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: purple,
                        minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.add_card),
                    label: const Text('Deposit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ScanPayScreen()));
                      _load();
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90D9),
                        minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan & Pay'),
                  ),
                ),
              ],
            ),
            if (!_data.hasPin) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.orange.shade50,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange),
                  title: const Text('Secure your wallet'),
                  subtitle: const Text('Set a 6-digit payment PIN'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PinSetupScreen()));
                    _load();
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Recent activity',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_data.recent.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('No transactions yet.\nMake your first deposit!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey))),
              )
            else
              ..._data.recent.map((t) {
                final isIn = t['direction'] == 'IN';
                final amountCents = int.tryParse(t['amount'] as String) ?? 0;
                final dollars = amountCents ~/ 100;
                final rem = (amountCents % 100).abs().toString().padLeft(2, '0');
                final status = t['status'] as String;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isIn ? Colors.green.shade50 : Colors.red.shade50,
                      child: Icon(
                        isIn ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isIn ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(_typeLabel(t['type'] as String)),
                    subtitle: Text(status == 'COMPLETED'
                        ? _dateLabel(t['createdAt'] as String)
                        : status),
                    trailing: Text(
                      '${isIn ? '+' : '-'}\$$dollars.$rem',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: status == 'COMPLETED'
                            ? (isIn ? Colors.green : Colors.red)
                            : Colors.grey,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'DEPOSIT':
        return 'Card deposit';
      case 'TRANSFER':
        return 'Transfer';
      case 'MERCHANT_PAYMENT':
        return 'Merchant payment';
      case 'REQUEST_PAYMENT':
        return 'Request payment';
      default:
        return type;
    }
  }

  String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
