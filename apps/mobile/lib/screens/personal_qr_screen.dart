import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Personal receive-money QR (PGW-28): anyone with the MiniPay app can scan
/// this to open a transfer prefilled with this user's email.
class PersonalQrScreen extends StatefulWidget {
  const PersonalQrScreen({super.key});

  @override
  State<PersonalQrScreen> createState() => _PersonalQrScreenState();
}

class _PersonalQrScreenState extends State<PersonalQrScreen> {
  String _name = '';
  String _email = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ApiClient.instance.dio.get('/auth/me');
      if (!mounted) return;
      setState(() {
        _name = me.data['displayName'] as String? ?? '';
        _email = me.data['email'] as String? ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Receive money')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.person, size: 44, color: purple),
                          const SizedBox(height: 8),
                          Text(_name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text(_email,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13)),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: Colors.grey.shade300),
                            ),
                            child: QrImageView(
                              data: 'minipay://user/$_email',
                              size: 230,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Scan with MiniPay to pay me',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          const SizedBox(height: 4),
                          const Text(
                              'The payer confirms the amount and pays with '
                              'fingerprint or PIN.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
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
