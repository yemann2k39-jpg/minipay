import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/bootstrap.dart';
import 'package:minipay/screens/collect_payment_screen.dart';
import 'package:minipay/screens/home_screen.dart';
import 'package:minipay/screens/integrations_screen.dart';
import 'package:minipay/screens/merchant_sales_screen.dart';
import 'package:minipay/screens/merchant_insights_screen.dart';
import 'package:minipay/screens/notifications_screen.dart';
import 'package:minipay/screens/security_screen.dart';
import 'package:minipay/screens/pin_setup.dart';
import 'package:minipay/services/local_notify.dart';
import 'package:minipay/screens/withdraw_screen.dart';

/// Merchant-mode home (PGW-18): shop balance, recent sales, and entry points
/// for Collect payment (PGW-19), Withdraw (PGW-22) and Integrations (PGW-21).
/// No consumer features (transfer / split / requests / deposit) are shown.
class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantData {
  String name = '';
  String code = '';
  String status = 'ACTIVE';
  String balanceMinor = '0';
  List<Map<String, dynamic>> recent = [];
  bool hasPin = false;
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  final _data = _MerchantData();
  bool _loading = true;
  int _unread = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _refreshUnread();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshUnread() async {
    try {
      final unread =
          await ApiClient.instance.dio.get('/notifications/unread-count');
      if (!mounted) return;
      setState(() => _unread = unread.data['count'] as int);
      // Surface new sales/refunds as system notifications (PGW-25).
      await LocalNotify.instance.syncFromServer();
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final shop = await ApiClient.instance.dio.get('/merchants/mine');
      _data.name = shop.data['name'] as String;
      _data.code = shop.data['code'] as String;
      _data.status = shop.data['status'] as String;
      _data.balanceMinor = shop.data['balanceMinor'] as String;
      final sales = await ApiClient.instance.dio
          .get('/merchants/mine/sales', queryParameters: {'take': 5});
      _data.recent =
          ((sales.data['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      try {
        final pinRes = await ApiClient.instance.dio.get('/auth/pin/status');
        _data.hasPin = pinRes.data['hasPin'] as bool;
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
      }
      await _refreshUnread();
      if (!mounted) return;
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

  void _showSaleDetails(Map<String, dynamic> sale) {
    final cents = int.tryParse(sale['amountMinor'] as String) ?? 0;
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sale details',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              saleDetailRow('Amount', '\$$dollars.$rem'),
              saleDetailRow('Order ref', sale['orderRef'] as String? ?? '—'),
              saleDetailRow(
                  'Description', sale['description'] as String? ?? '—'),
              saleDetailRow('Status', sale['status'] as String? ?? '—'),
              saleDetailRow(
                  'Created', saleDateLabel(sale['createdAt'] as String?)),
              if (sale['paidAt'] != null)
                saleDetailRow(
                    'Paid at', saleDateLabel(sale['paidAt'] as String)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MerchantSalesScreen()));
                },
                child: const Text('Open full sales list for refunds'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final purple = Theme.of(context).colorScheme.primary;
    final frozen = _data.status == 'FROZEN';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_data.name.isEmpty ? 'My Business' : _data.name),
        actions: [
          // Personal view (PGW-23): the owner's own wallet in the same app.
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Personal view',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HomeScreen(embedPersonal: true)));
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Profile & security',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SecurityScreen())),
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text(_unread > 9 ? '9+' : '$_unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationsScreen()));
              _load();
            },
          ),
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
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Shop balance card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4C81),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Business balance',
                        style: TextStyle(
                            color: Colors.white.withAlpha(179))),
                    const SizedBox(height: 6),
                    Text(_balanceText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${_data.code} · SGD',
                        style: TextStyle(
                            color: Colors.white.withAlpha(153),
                            fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (frozen) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE57373)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.report,
                          color: Color(0xFFC62828), size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your business account is frozen. You can view '
                          'your balance and sales, but new payment requests '
                          'and payouts are disabled. Contact support if you '
                          'think this is a mistake.',
                          style: TextStyle(
                              color: Color(0xFFB71C1C), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Collect payment (PGW-19)
              FilledButton.icon(
                onPressed: frozen
                    ? null
                    : () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const CollectPaymentScreen()));
                        _load();
                      },
                style: FilledButton.styleFrom(
                    backgroundColor: purple,
                    disabledBackgroundColor: Colors.grey.shade300,
                    minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Collect payment'),
              ),
              const SizedBox(height: 12),
              // Withdraw to wallet (PGW-22)
              FilledButton.tonalIcon(
                onPressed: frozen
                    ? null
                    : () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => WithdrawScreen(
                                businessBalanceMinor: _data.balanceMinor,
                                businessName: _data.name)));
                        _load();
                      },
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor:
                        Theme.of(context).colorScheme.primary,
                    disabledForegroundColor: Colors.grey,
                    minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.account_balance),
                label: const Text('Withdraw to wallet'),
              ),
              const SizedBox(height: 12),
              // Integrations (PGW-21)
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const IntegrationsScreen()));
                },
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor:
                        Theme.of(context).colorScheme.primary,
                    disabledForegroundColor: Colors.grey,
                    minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.integration_instructions),
                label: const Text('API keys & integrations'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Recent sales',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  // Sales insights (PGW-27).
                  IconButton(
                    icon: const Icon(Icons.bar_chart, size: 20),
                    tooltip: 'Sales insights',
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const MerchantInsightsScreen())),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MerchantSalesScreen())),
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_data.recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No sales yet.\nPayments to your shop '
                          'will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey))),
                )
              else
                ..._data.recent
                    .map((s) => saleTile(s, _showSaleDetails)),
            ],
          ),
        ),
      ),
    );
  }
}
