import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minipay/api/api_client.dart';

/// Security & settings (PGW-29/30/31): profile, daily limit, payment PIN,
/// password, active sessions.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  Map<String, dynamic>? _prefs;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _appLock = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appLock = await ApiClient.instance.readAppLockEnabled();
    try {
      final results = await Future.wait([
        ApiClient.instance.dio.get('/auth/preferences'),
        ApiClient.instance.dio.get('/auth/sessions'),
      ]);
      if (!mounted) return;
      setState(() {
        _prefs = results[0].data as Map<String, dynamic>;
        _sessions =
            (results[1].data['sessions'] as List).cast<Map<String, dynamic>>();
        _appLock = appLock;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(apiError(e).message);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  String _fmtLimit() {
    final v = _prefs?['dailySpendLimitMinor'];
    if (v == null) return 'No daily limit';
    final cents = int.tryParse('$v') ?? 0;
    return 'SGD ${(cents ~/ 100).toString()}.${(cents % 100).toString().padLeft(2, '0')} / day';
  }

  Future<bool?> _confirm(String title, String body,
      {String confirmLabel = 'Confirm'}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
  }

  Future<String?> _prompt(
      {required String title,
      String? label,
      bool obscure = false,
      TextInputType? keyboard,
      List<TextInputFormatter>? inputFormatters}) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: obscure,
          keyboardType: keyboard,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    return (res == null || res.isEmpty) ? null : res;
  }

  // -- Actions ------------------------------------------------------------

  Future<void> _editName() async {
    final name = await _prompt(
        title: 'Your name',
        label: 'Display name',
        keyboard: TextInputType.name);
    if (name == null) return;
    try {
      await ApiClient.instance.dio
          .patch('/auth/me', data: {'displayName': name});
      _toast('Name updated');
      _load();
    } catch (e) {
      _toast(apiError(e).message);
    }
  }

  Future<void> _editLimit() async {
    final current = _prefs?['dailySpendLimitMinor'];
    final input = await _prompt(
      title: 'Daily transfer limit',
      label: current == null
          ? 'Limit in SGD (blank = none)'
          : 'Limit in SGD (current: ${(int.tryParse('$current') ?? 0) / 100})',
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
    if (input == null) return;
    final clean = input.replaceAll(RegExp(r'[^0-9.]'), '');
    final cents = clean.isEmpty
        ? null
        : ((double.tryParse(clean) ?? 0) * 100).round();
    try {
      await ApiClient.instance.dio.put('/auth/preferences',
          data: {'dailySpendLimitMinor': cents});
      _toast(cents == null ? 'Limit removed' : 'Daily limit saved');
      _load();
    } catch (e) {
      _toast(apiError(e).message);
    }
  }

  Future<void> _changePin() async {
    final current = await _prompt(
        title: 'Change payment PIN',
        label: 'Current 6-digit PIN',
        obscure: true,
        keyboard: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]);
    if (current == null) return;
    final next = await _prompt(
        title: 'Change payment PIN',
        label: 'New 6-digit PIN',
        obscure: true,
        keyboard: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]);
    if (next == null) return;
    try {
      await ApiClient.instance.dio.post('/auth/pin/change',
          data: {'currentPin': current, 'newPin': next});
      _toast('Payment PIN changed');
    } catch (e) {
      _toast(apiError(e).message);
    }
  }

  Future<void> _resetPin() async {
    final password = await _prompt(
        title: 'Forgot PIN?',
        label: 'Account password',
        obscure: true);
    if (password == null) return;
    final next = await _prompt(
        title: 'Forgot PIN?',
        label: 'New 6-digit PIN',
        obscure: true,
        keyboard: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]);
    if (next == null) return;
    try {
      await ApiClient.instance.dio.post('/auth/pin/reset',
          data: {'password': password, 'newPin': next});
      // Update the local biometric-PIN copy so fingerprint pay keeps working.
      await ApiClient.instance.saveLocalPin(next);
      _toast('Payment PIN reset');
    } catch (e) {
      _toast(apiError(e).message);
    }
  }

  Future<void> _changePassword() async {
    final current = await _prompt(
        title: 'Change password',
        label: 'Current password',
        obscure: true);
    if (current == null) return;
    final next = await _prompt(
        title: 'Change password',
        label: 'New password (min 8 chars)',
        obscure: true);
    if (next == null) return;
    final ok = await _confirm('Sign out other devices?',
        'Changing your password signs out all other devices for safety.',
        confirmLabel: 'Change');
    if (ok != true) return;
    try {
      await ApiClient.instance.dio.post('/auth/change-password',
          data: {'currentPassword': current, 'newPassword': next});
      _toast('Password changed — other devices signed out');
    } catch (e) {
      _toast(apiError(e).message);
    }
  }

  Future<void> _logoutOthers() async {
    final ok = await _confirm('Sign out other devices?',
        'All other phones/devices logged into this account will need to sign in again.',
        confirmLabel: 'Sign out');
    if (ok != true) return;
    try {
      final res = await ApiClient.instance.dio.post('/auth/logout-others');
      _toast('Signed out ${res.data['revoked']} session(s)');
      _load();
    } catch (e) {
      _toast(apiError(e).message);
    }
  }

  String _deviceLabel(Map<String, dynamic> s) {
    final ua = (s['userAgent'] as String?) ?? 'Unknown device';
    // Human-friendly: strip the tech noise from user agents.
    if (ua.contains('okhttp')) return 'MiniPay app (Android)';
    if (ua.contains('Dart')) return 'MiniPay app';
    if (ua.contains('iPhone')) return 'iPhone';
    if (ua.contains('Android')) return 'Android device';
    if (ua.contains('Chrome')) return 'Chrome browser';
    return ua.length > 32 ? '${ua.substring(0, 32)}…' : ua;
  }

  String _date(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Profile & security')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Profile ------------------------------------------------
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                            backgroundColor: purple,
                            child: const Icon(Icons.person,
                                color: Colors.white)),
                        title: Text(_prefs?['displayName'] as String? ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(_prefs?['email'] as String? ?? ''),
                        trailing: const Icon(Icons.edit, size: 20),
                        onTap: _editName,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Spending limit ----------------------------------------
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.speed),
                        title: const Text('Daily transfer limit'),
                        subtitle: Text(_fmtLimit()),
                        trailing: const Icon(Icons.edit, size: 20),
                        onTap: _editLimit,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // PIN & password ----------------------------------------
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.fingerprint),
                            title: const Text('App lock'),
                            subtitle: const Text(
                                'Require fingerprint or PIN each time you open MiniPay'),
                            value: _appLock,
                            onChanged: (v) async {
                              setState(() => _appLock = v);
                              await ApiClient.instance.saveAppLockEnabled(v);
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.password),
                            title: const Text('Change payment PIN'),
                            subtitle: const Text(
                                'Used for payments and app unlock'),
                            onTap: _changePin,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.pin_outlined),
                            title: const Text('Forgot your PIN?'),
                            subtitle: const Text(
                                'Reset it with your account password'),
                            onTap: _resetPin,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Change password'),
                            subtitle:
                                const Text('Signs out other devices'),
                            onTap: _changePassword,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Sessions ----------------------------------------------
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Row(
                              children: [
                                const Icon(Icons.devices),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                      'Active sessions (${_sessions.length})',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                          ..._sessions.map(
                            (s) => ListTile(
                              leading: Icon(
                                s['current'] == true
                                    ? Icons.smartphone
                                    : Icons.devices_other,
                                color: s['current'] == true ? purple : null,
                              ),
                              title: Text(_deviceLabel(s),
                                  style: TextStyle(
                                      fontWeight: s['current'] == true
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              subtitle: Text(
                                  '${s['ip'] ?? 'unknown IP'} · since ${_date(s['createdAt'] as String)}'
                                  '${s['current'] == true ? ' · this device' : ''}'),
                              dense: true,
                            ),
                          ),
                          if (_sessions.any((s) => s['current'] != true))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: OutlinedButton(
                                onPressed: _logoutOthers,
                                child: const Text('Sign out other devices'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
