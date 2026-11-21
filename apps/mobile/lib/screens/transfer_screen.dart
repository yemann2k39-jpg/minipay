import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:minipay/api/api_client.dart';
import 'package:minipay/screens/success_screen.dart';
import 'package:minipay/widgets/pin_entry_pad.dart';

class _Recipient {
  final String userId;
  final String displayName;
  final String? email;
  _Recipient({required this.userId, required this.displayName, this.email});
}

/// Transfer money: type an email/phone (verified against the platform) or
/// pick a contact below. Biometric payment if enrolled, otherwise PIN.
class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, this.prefillEmail});

  /// Personal-QR flow (PGW-28): recipient email preloaded from a scan.
  final String? prefillEmail;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _recipientCtrl = TextEditingController();
  final _amount = TextEditingController();
  final _localAuth = LocalAuthentication();

  _Recipient? _recipient;
  List<Map<String, dynamic>> _contacts = [];
  bool _loadingContacts = true;
  bool _checking = false;
  String? _recipientError;
  bool _biometricAvailable = false;
  String? _localPin;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _checkBiometric();
    // Personal-QR flow: prefill the recipient and verify immediately.
    if (widget.prefillEmail != null && widget.prefillEmail!.isNotEmpty) {
      _recipientCtrl.text = widget.prefillEmail!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _recipientCtrl.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _clearRecipient() async {
    _recipientCtrl.clear();
    _amount.clear();
    setState(() {
      _recipient = null;
      _recipientError = null;
    });
  }

  Future<void> _loadContacts() async {
    try {
      final res = await ApiClient.instance.dio.get('/contacts');
      if (!mounted) return;
      setState(() {
        _contacts = (res.data as List).cast<Map<String, dynamic>>();
        _loadingContacts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingContacts = false);
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
        localizedReason: 'Confirm your transfer',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _lookup() async {
    final q = _recipientCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _checking = true;
      _recipientError = null;
    });
    try {
      final res = await ApiClient.instance.dio
          .get('/contacts/lookup', queryParameters: {'query': q});
      if (!mounted) return;
      final newRecipient = _Recipient(
        userId: res.data['userId'] as String,
        displayName: res.data['displayName'] as String,
        email: res.data['email'] as String?,
      );
      // New recipient => start a fresh amount.
      final isSame = _recipient?.userId == newRecipient.userId;
      setState(() {
        _recipient = newRecipient;
        _checking = false;
        if (!isSame) _amount.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recipient = null;
        _recipientError = apiError(e).message;
        _checking = false;
      });
    }
  }

  void _selectRecipient(String userId, String displayName, String? email) {
    setState(() {
      _recipient = _Recipient(
          userId: userId, displayName: displayName, email: email);
      _recipientError = null;
      _recipientCtrl.text = email ?? displayName;
    });
  }

  Future<void> _addContact() async {
    final query = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add contact',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: query,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Email or phone number',
                prefixIcon: Icon(Icons.person_search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.instance.dio
          .post('/contacts', data: {'query': query.text.trim()});
      _loadContacts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          backgroundColor: Colors.red.shade300,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _removeContact(Map<String, dynamic> c) async {
    try {
      await ApiClient.instance.dio.delete('/contacts/${c['id']}');
      _loadContacts();
    } catch (_) {}
  }

  Future<void> _payWithPin(String pin) async {
    final cents = _amountCents;
    if (cents < 100 || cents > 500000) {
      throw Exception('Amount must be between SGD 1.00 and 5,000.00');
    }
    try {
      await ApiClient.instance.dio.post('/wallet/transfer', data: {
        'toUserId': _recipient!.userId,
        'amount': cents,
        'pin': pin,
      });
      if (!mounted) return;
      final dollars = cents ~/ 100;
      final rem = (cents % 100).toString().padLeft(2, '0');
      final nav = Navigator.of(context);
      // Return to home FIRST, then show the success page on top of it —
      // Done pops back to home.
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: 'Transfer successful',
          amountText: 'S\$$dollars.$rem',
          subtitleLines: ['To ${_recipient!.displayName}'],
        ),
      ));
    } catch (e) {
      throw Exception(apiError(e).message);
    }
  }

  int get _amountCents {
    final v = double.tryParse(_amount.text.trim());
    return v == null ? 0 : (v * 100).round();
  }

  Future<void> _payWithBiometrics() async {
    final cents = _amountCents;
    if (cents < 100 || cents > 500000) {
      setState(() =>
          _recipientError = 'Amount must be between SGD 1.00 and 5,000.00');
      return;
    }
    setState(() => _recipientError = null);
    if (!await _confirmSend(cents)) return;
    final ok = await _biometricAuth();
    if (!ok) return;
    final stored = _localPin ?? await ApiClient.instance.readLocalPin();
    if (stored == null) {
      _openPinPad();
      return;
    }
    try {
      await _payWithPin(stored);
    } catch (_) {
      await ApiClient.instance.clearLocalPin();
      if (!mounted) return;
      setState(() => _localPin = null);
      _openPinPad();
    }
  }

  /// Confirm-before-send (PGW-29): recipient name + amount, one last look.
  Future<bool> _confirmSend(int cents) async {
    final dollars = cents ~/ 100;
    final rem = (cents % 100).toString().padLeft(2, '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm transfer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send  S\$$dollars.$rem to',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Text(_recipient!.displayName,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            if (_recipient!.email != null)
              Text(_recipient!.email!,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send')),
        ],
      ),
    );
    return ok == true;
  }

  void _openPinPad() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Confirm PIN')),
        body: SafeArea(
          child: PinEntryPad(
            title: 'Send to ${_recipient!.displayName}',
            onSubmit: _payWithPin,
          ),
        ),
      ),
    ));
  }

  void _startSend() async {
    final cents = _amountCents;
    if (cents < 100 || cents > 500000) {
      setState(() =>
          _recipientError = 'Amount must be between SGD 1.00 and 5,000.00');
      return;
    }
    if (!await _confirmSend(cents)) return;
    _openPinPad();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bioReady = _biometricAvailable && _localPin != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Recipient ---
              TextField(
                controller: _recipientCtrl,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _lookup(),
                decoration: InputDecoration(
                  labelText: 'Recipient email or phone',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: _checking
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextButton.icon(
                            onPressed: _lookup,
                            icon: const Icon(Icons.person_search, size: 18),
                            label: const Text('Check'),
                          ),
                        ),
                ),
              ),
              if (_recipientError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_recipientError!,
                      style: const TextStyle(color: Colors.red)),
                ),
              if (_recipient != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: primary,
                      child: Text(
                          _recipient!.displayName.isNotEmpty
                              ? _recipient!.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(_recipient!.displayName,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_recipient!.email ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearRecipient,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                        color: primary),
                    hintText: '0.00',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                if (bioReady)
                  FilledButton.icon(
                    onPressed: _payWithBiometrics,
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90D9),
                        minimumSize: const Size.fromHeight(52)),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Transfer with fingerprint'),
                  ),
                if (bioReady) const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _startSend,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: BorderSide(color: Colors.grey.shade400)),
                  child: Text(bioReady ? 'Use PIN instead' : 'Transfer with PIN'),
                ),
              ],
              const SizedBox(height: 24),
              // --- Contacts ---
              Row(
                children: [
                  Text('Contacts',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.person_add), onPressed: _addContact),
                ],
              ),
              if (_loadingContacts)
                const Center(child: CircularProgressIndicator())
              else if (_contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No contacts yet — add one with + above.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ..._contacts.map((c) {
                  final name = c['displayName'] as String? ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer)),
                      ),
                      title: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text((c['email'] as String?) ?? ''),
                      onTap: () => _selectRecipient(
                          c['userId'] as String, name, c['email'] as String?),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _removeContact(c),
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
}
