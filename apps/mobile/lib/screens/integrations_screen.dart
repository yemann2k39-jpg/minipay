import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';

/// API keys & integrations (PGW-21): create the first key (shown ONCE),
/// rotate with confirmation. Includes a short integration guide.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _hasKey = false;
  String? _freshKey; // only set right after create/rotate

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/merchants/mine/keys');
      if (!mounted) return;
      setState(() {
        _hasKey = res.data['hasKey'] as bool;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async => _keyAction(
        () => ApiClient.instance.dio.post('/merchants/mine/keys'),
        'API key created. Copy it now — it will not be shown again.',
      );

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rotate API key?'),
        content: const Text(
            'Your current API key stops working immediately. Any website '
            'using it will get errors until you update it with the new key.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Rotate')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _keyAction(
      () => ApiClient.instance.dio.post('/merchants/mine/keys/rotate'),
      'API key rotated. Copy the new key now — it will not be shown again.',
    );
  }

  Future<void> _keyAction(Future<Response> Function() call, String message) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      if (!mounted) return;
      setState(() {
        _freshKey = res.data['apiKey'] as String;
        _hasKey = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)));
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map &&
              (e.response!.data as Map)['message'] != null
          ? (e.response!.data as Map)['message'].toString()
          : 'Could not create the key';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('API keys & integrations')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.vpn_key,
                                  color: Color(0xFF0F4C81)),
                              const SizedBox(width: 8),
                              Text('Your API key',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_freshKey != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F4F8),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.grey.shade300),
                              ),
                              child: SelectableText(_freshKey!,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13)),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: _freshKey!));
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content:
                                                Text('API key copied')));
                                  },
                                  style: FilledButton.styleFrom(
                                      backgroundColor: purple),
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copy key'),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Shown only once. Store it safely.',
                                    style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text(
                              _hasKey
                                  ? 'An API key exists for this business '
                                      '(hidden for safety). Rotate to get '
                                      'a new one.'
                                  : 'No API key yet. Create one to accept '
                                      'payments from your website.',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (!_hasKey)
                            FilledButton.icon(
                              onPressed:
                                  _busy ? null : _create,
                              style: FilledButton.styleFrom(
                                  backgroundColor: purple,
                                  minimumSize:
                                      const Size.fromHeight(48)),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.add),
                              label: const Text('Create API key'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _rotate,
                              style: OutlinedButton.styleFrom(
                                  minimumSize:
                                      const Size.fromHeight(48)),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Rotate API key'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Accept payments on your website',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text(
                            '1. Create a checkout from your server:\n\n'
                            'POST http://<your-minipay-host>:3000/'
                            'merchant-api/checkout\n'
                            'Header: X-API-Key: <your key>\n'
                            'Body: { "orderRef": "ORDER-1", '
                            '"amountMinor": 1250, "description": "T-shirt", '
                            '"callbackUrl": "https://your.site/callback" }\n\n'
                            '2. Send the customer to the returned '
                            'checkoutUrl — they pay by QR or email + PIN.\n\n'
                            '3. We POST a signed callback '
                            '(X-MiniPay-Signature = HMAC-SHA256 of the raw '
                            'body with your API key) to your callbackUrl '
                            'when the payment completes.\n\n'
                            'Amounts are in minor units '
                            '(1250 = S\$12.50). Sessions expire in 15 '
                            'minutes.',
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
