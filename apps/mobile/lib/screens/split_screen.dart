import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:minipay/api/api_client.dart';

/// Split bill — entry screen listing my split sessions.
class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitParticipant {
  _SplitParticipant({
    required this.userId,
    required this.displayName,
    required this.shareAmount,
    this.requestStatus,
    this.isCreator = false,
  });

  factory _SplitParticipant.fromJson(Map<String, dynamic> j) {
    // Backend sends a flat per-participant `status` (from the linked request)
    // plus `isCreator` — the creator paid the bill up front.
    final status = j['status'] == null ? null : '${j['status']}';
    return _SplitParticipant(
      userId: '${j['userId'] ?? ''}',
      displayName: '${j['displayName'] ?? ''}',
      shareAmount: int.tryParse('${j['shareAmount']}') ?? 0,
      requestStatus: status,
      isCreator: j['isCreator'] == true,
    );
  }

  final String userId;
  final String displayName;
  final int shareAmount;

  /// Status of the money request backing this participant's share.
  final String? requestStatus;

  /// The creator paid the bill up front — never asked to pay again.
  final bool isCreator;

  /// Zero-share participants get no money request (nothing to pay).
  bool get isZeroShare => shareAmount == 0 && requestStatus == null;

  /// Needs a request sent from the detail page (including re-asking after
  /// a decline/cancel).
  bool get needsRequest =>
      !isCreator &&
      !isZeroShare &&
      (requestStatus == null ||
          requestStatus == 'DECLINED' ||
          requestStatus == 'CANCELLED');

  bool get isPaid => isCreator || requestStatus == 'PAID';
  bool get isPending =>
      !isCreator && !isZeroShare && requestStatus != null && !isPaid;
}

class _SplitSession {
  _SplitSession({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.participants,
    required this.totalMinor,
  });

  factory _SplitSession.fromJson(Map<String, dynamic> j) {
    final participants = ((j['participants'] as List?) ?? const [])
        .map((p) => _SplitParticipant.fromJson(p as Map<String, dynamic>))
        .toList();
    return _SplitSession(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      status: '${j['status'] ?? ''}',
      createdAt: '${j['createdAt'] ?? ''}',
      participants: participants,
      totalMinor: int.tryParse('${j['totalMinor']}') ??
          participants.fold(0, (sum, p) => sum + p.shareAmount),
    );
  }

  final String id;
  final String title;
  final String status;
  final String createdAt;
  final List<_SplitParticipant> participants;
  final int totalMinor;

  int get total => totalMinor;

  int get paidCount => participants.where((p) => p.isPaid).length;
  int get pendingCount => participants.where((p) => p.isPending).length;
}

class _Contact {
  _Contact({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phone,
  });

  factory _Contact.fromJson(Map<String, dynamic> j) => _Contact(
        userId: '${j['userId'] ?? ''}',
        displayName: '${j['displayName'] ?? ''}',
        email: '${j['email'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
      );

  final String userId;
  final String displayName;
  final String email;
  final String phone;
}

/// One editable line item while building a split.
class _EditableItem {
  _EditableItem({
    required this.nameController,
    required this.priceController,
    Set<String> assignedUserIds = const {},
  }) : assignedUserIds = assignedUserIds.toSet();

  final TextEditingController nameController;
  final TextEditingController priceController;
  final Set<String> assignedUserIds;

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

class _SplitScreenState extends State<SplitScreen> {
  List<_SplitSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/split');
      if (!mounted) return;
      // Backend shape: { sessions: [...] }.
      setState(() {
        _sessions = (((res.data as Map<String, dynamic>)['sessions'] as List?) ??
                const [])
            .map((j) => _SplitSession.fromJson(j as Map<String, dynamic>))
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

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SplitCreateScreen()));
    if (mounted) _load();
  }

  Future<void> _openDetail(_SplitSession s) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SplitDetailScreen(sessionId: s.id)));
    if (mounted) _load();
  }

  String _money(int cents) {
    final d = cents ~/ 100;
    final r = (cents % 100).abs().toString().padLeft(2, '0');
    final sign = cents < 0 ? '-' : '';
    return 'S\$$sign$d.$r';
  }

  String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split bill')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.call_split),
        label: const Text('New split'),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _sessions.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'No splits yet.\nTap "New split" to scan a receipt '
                                'and share the cost.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sessions.length,
                        itemBuilder: (ctx, i) {
                          final s = _sessions[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDetail(s),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(s.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _money(s.total),
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(_dateLabel(s.createdAt),
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12)),
                                        const Spacer(),
                                        Text(
                                          '${s.paidCount} paid · ${s.pendingCount} pending',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: s.pendingCount == 0
                                                  ? Colors.green
                                                  : Colors.orange),
                                        ),
                                      ],
                                    ),
                                    if (s.participants.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: s.participants
                                            .map((p) => _StatusChip(
                                                label:
                                                    '${p.displayName} · ${p.isPaid ? 'PAID' : 'PENDING'}',
                                                paid: p.isPaid))
                                            .toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

/// Small colored participant chip: green PAID, orange PENDING, gray
/// NOT INCLUDED, red DECLINED/CANCELLED.
class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.paid, this.neutral = false, this.danger = false});

  final String label;
  final bool paid;
  final bool neutral;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? const Color(0xFFFDECEA)
        : neutral
            ? const Color(0xFFEFF1F4)
            : paid
                ? const Color(0xFFE5F6EC)
                : const Color(0xFFFDF1E0);
    final border = danger
        ? const Color(0xFFF3C1BC)
        : neutral
            ? const Color(0xFFD6DBE2)
            : paid
                ? const Color(0xFFBFE6CF)
                : const Color(0xFFF3D9AE);
    final fg = danger
        ? const Color(0xFFB71C1C)
        : neutral
            ? const Color(0xFF6B7280)
            : paid
                ? const Color(0xFF1B7F4B)
                : const Color(0xFFB26A00);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Create flow: receipt scan, people, item assignment, extra, then submit.
class SplitCreateScreen extends StatefulWidget {
  const SplitCreateScreen({super.key});

  @override
  State<SplitCreateScreen> createState() => _SplitCreateScreenState();
}

class _SplitCreateScreenState extends State<SplitCreateScreen> {
  final _titleController = TextEditingController();
  final _extraController = TextEditingController();
  final _discountController = TextEditingController();
  final _picker = ImagePicker();

  final List<_EditableItem> _items = [];
  final List<_Contact> _participants = [];
  List<_Contact> _contacts = [];
  String? _creatorId;

  bool _scanning = false;
  bool _loadingContacts = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCreatorId();
  }

  Future<void> _loadCreatorId() async {
    final me = await ApiClient.instance.currentUserId;
    if (mounted) setState(() => _creatorId = me);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _extraController.dispose();
    _discountController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  String _money(int cents) {
    final d = cents ~/ 100;
    final r = (cents % 100).abs().toString().padLeft(2, '0');
    return 'S\$$d.$r';
  }

  String _minorToDollarsText(int minor) {
    final d = minor ~/ 100;
    final r = (minor % 100).abs().toString().padLeft(2, '0');
    return '$d.$r';
  }

  /// Live total shown in Step 1: items + extra - discount (never negative).
  int _liveTotalMinor() {
    final items = _items.fold<int>(0, (s, it) {
      final v = _dollarsToMinor(it.priceController.text);
      return s + (v ?? 0);
    });
    final extra = _dollarsToMinor(_extraController.text) ?? 0;
    final discount = _dollarsToMinor(_discountController.text) ?? 0;
    final total = items + extra - discount;
    return total < 0 ? 0 : total;
  }

  /// Returns null when the text is not a valid amount.
  int? _dollarsToMinor(String input, {bool allowNegative = false}) {
    final text = input.trim().replaceAll('\$', '').replaceAll(',', '');
    if (text.isEmpty) return null;
    final v = double.tryParse(text);
    // NaN/Infinity pass tryParse but crash .round() — reject explicitly.
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (!allowNegative && v < 0) return null;
    return (v * 100).round();
  }

  // ------------------------------------------------------------------
  // Step A: receipt
  // ------------------------------------------------------------------

  Future<void> _scanReceipt(ImageSource source) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (file == null) {
        if (mounted) setState(() => _scanning = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final mime = (file.mimeType?.isNotEmpty ?? false)
          ? file.mimeType!
          : (file.path.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      final res = await ApiClient.instance.dio.post('/split/scan', data: {
        'imageBase64': base64Encode(bytes),
        'mimeType': mime,
      });
      if (!mounted) return;
      final scanned = ((res.data['items'] as List?) ?? const [])
          .map((j) => j as Map<String, dynamic>)
          .toList();
      if (scanned.isEmpty) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No items were detected on this receipt.'),
            behavior: SnackBarBehavior.floating));
        return;
      }
      setState(() {
        for (final j in scanned) {
          final minor = int.tryParse('${j['priceMinor']}') ?? 0;
          _items.add(_EditableItem(
            nameController: TextEditingController(text: '${j['name'] ?? ''}'),
            priceController:
                TextEditingController(text: _minorToDollarsText(minor)),
          ));
        }
        _scanning = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      final friendly =
          e.code == 'camera_access_denied'
              ? 'Camera access was denied. Allow camera access in Settings and try again.'
              : e.code == 'photo_access_denied'
                  ? 'Photo access was denied. Allow photo access in Settings and try again.'
                  : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendly ?? 'Could not pick the image: ${e.message ?? e.code}'),
          backgroundColor: friendly != null ? Colors.red.shade300 : null,
          behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          behavior: SnackBarBehavior.floating));
    }
  }

  void _addManualItem() {
    setState(() {
      _items.add(_EditableItem(
        nameController: TextEditingController(),
        priceController: TextEditingController(),
      ));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  // ------------------------------------------------------------------
  // Step B: people
  // ------------------------------------------------------------------

  Future<void> _openContacts() async {
    if (_loadingContacts) return;
    if (_contacts.isEmpty) {
      setState(() => _loadingContacts = true);
      try {
        final res = await ApiClient.instance.dio.get('/contacts');
        if (!mounted) return;
        setState(() {
          _contacts = ((res.data as List?) ?? const [])
              .map((j) => _Contact.fromJson(j as Map<String, dynamic>))
              .toList();
          _loadingContacts = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _loadingContacts = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(apiError(e).message),
            behavior: SnackBarBehavior.floating));
        return;
      }
    }
    if (!mounted) return;
    final me = await ApiClient.instance.currentUserId;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add people',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Participants are the people who pay. You are not included.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _contacts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No contacts yet.',
                                  style: TextStyle(color: Colors.grey))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _contacts.length,
                          itemBuilder: (ctx, i) {
                            final c = _contacts[i];
                            // Never offer yourself as a participant.
                            if (me != null && c.userId == me) {
                              return const SizedBox.shrink();
                            }
                            final selected = _participants
                                .any((p) => p.userId == c.userId);
                            return CheckboxListTile(
                              value: selected,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              dense: true,
                              title: Text(c.displayName),
                              subtitle: c.email.isEmpty
                                  ? null
                                  : Text(c.email,
                                      style: const TextStyle(fontSize: 12)),
                              onChanged: (_) {
                                _toggleParticipant(c);
                                setSheetState(() {});
                              },
                            );
                          },
                        ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleParticipant(_Contact c) {
    setState(() {
      final idx = _participants.indexWhere((p) => p.userId == c.userId);
      if (idx >= 0) {
        _participants.removeAt(idx);
        // Strip the removed person from any item assignments.
        for (final it in _items) {
          it.assignedUserIds.remove(c.userId);
        }
      } else {
        _participants.add(c);
      }
    });
  }

  // ------------------------------------------------------------------
  // Step C: assignment
  // ------------------------------------------------------------------

  void _toggleAssignment(_EditableItem item, String userId) {
    setState(() {
      if (item.assignedUserIds.contains(userId)) {
        item.assignedUserIds.remove(userId);
      } else {
        item.assignedUserIds.add(userId);
      }
    });
  }

  // ------------------------------------------------------------------
  // Submit
  // ------------------------------------------------------------------

  Future<void> _createSplit() async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Please enter a title for the split.');
      return;
    }
    if (_participants.isEmpty) {
      _showError('Add at least one person who pays.');
      return;
    }
    if (_items.isEmpty) {
      _showError('Add at least one item. Scan a receipt or add it manually.');
      return;
    }
    final itemPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final name = item.nameController.text.trim();
      if (name.isEmpty) {
        _showError('Item ${i + 1} needs a name.');
        return;
      }
      final minor = _dollarsToMinor(item.priceController.text);
      if (minor == null || minor <= 0) {
        _showError('Item "$name" needs a valid price.');
        return;
      }
      itemPayload.add({
        'name': name,
        'priceMinor': minor,
        'assignedUserIds': item.assignedUserIds.toList(),
      });
    }
    final extraMinor = _dollarsToMinor(_extraController.text) ?? 0;
    final discountMinor = _dollarsToMinor(_discountController.text) ?? 0;
    final itemsTotal = itemPayload.fold<int>(0, (s, e) => s + (e['priceMinor'] as int));
    if (discountMinor > itemsTotal + extraMinor) {
      _showError('The discount cannot be more than the bill total.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiClient.instance.dio.post('/split', data: {
        'title': title,
        'participantUserIds':
            _participants.map((p) => p.userId).toList(),
        'items': itemPayload,
        'extraMinor': extraMinor,
        'discountMinor': discountMinor,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Split created')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          backgroundColor: Colors.red.shade300,
          behavior: SnackBarBehavior.floating));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade300,
        behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New split')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(
              step: null,
              title: 'Title',
              child: TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'e.g. Dinner', prefixIcon: Icon(Icons.label_outline)),
              ),
            ),
            _section(
              step: 'Step 1',
              title: 'Receipt',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_scanning) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Scanning receipt, this can take a few seconds...',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _scanning ? null : () => _scanReceipt(ImageSource.camera),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade400)),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Scan receipt'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scanning
                              ? null
                              : () => _scanReceipt(ImageSource.gallery),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade400)),
                          icon: const Icon(Icons.photo_outlined),
                          label: const Text('Choose photo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _scanning ? null : _addManualItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add item manually'),
                  ),
                  ..._buildItemEditors(),
                  const SizedBox(height: 8),
                  // Live total (items + extra - discount). Not editable —
                  // edit the items above instead.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Text('Total',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(_money(_liveTotalMinor()),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _section(
              step: 'Step 2',
              title: 'People',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // You are always included — you paid the bill.
                      InputChip(
                        label: const Text('You'),
                        avatar: Icon(Icons.person,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                        onPressed: null,
                      ),
                      ..._participants
                          .map((p) => InputChip(
                                label: Text(p.displayName),
                                onDeleted: () => _toggleParticipant(p),
                              )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FilledButton.tonalIcon(
                    onPressed: _loadingContacts ? null : _openContacts,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Theme.of(context).colorScheme.primary),
                    icon: _loadingContacts
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.group_add),
                    label: const Text('Add people to ask'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You are automatically included (you paid the bill). '
                    'Add the people who owe you their share.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            _section(
              step: 'Step 3',
              title: 'Items',
              hint: 'Choose who pays for each item — including You. Leave '
                  'everyone unchecked to split equally among everyone.',
              child: _items.isEmpty
                  ? const Text('No items yet. Scan a receipt or add one manually.',
                      style: TextStyle(color: Colors.grey, fontSize: 13))
                  : Column(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          _buildAssignmentCard(_items[i]),
                      ],
                    ),
            ),
            _section(
              step: 'Step 4',
              title: 'Extra & Discount',
              hint: 'Extra = tip added to the total. Discount = subtracted '
                  'from the total (e.g. when the AI missed a voucher line).',
              child: Column(
                children: [
                  TextField(
                    controller: _extraController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Extra / Tip (SGD)',
                      prefixIcon: Icon(Icons.add_circle_outline),
                      hintText: '0',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _discountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Discount (SGD)',
                      prefixIcon: Icon(Icons.remove_circle_outline),
                      hintText: '0',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _createSplit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Create split'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItemEditors() {
    if (_items.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      for (var i = 0; i < _items.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _items[i].nameController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Item name', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _items[i].priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Price (SGD)', isDense: true),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeItem(i),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove item',
                ),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _buildAssignmentCard(_EditableItem item) {
    final name = item.nameController.text.trim();
    final minor = _dollarsToMinor(item.priceController.text);
    // Assignable people = You (creator, always included) + contacts.
    final me = _creatorId;
    final assignables = <(String, String)>[
      if (me != null) (me, 'You'),
      ..._participants.map((p) => (p.userId, p.displayName)),
    ];
    final assignedNames = assignables
        .where((a) => item.assignedUserIds.contains(a.$1))
        .map((a) => a.$2)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          title: Text(
            name.isEmpty ? 'Unnamed item' : name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            minor == null
                ? 'Price not set'
                : assignedNames.isEmpty
                    ? '${_money(minor)} · Split equally among everyone'
                    : '${_money(minor)} · ${assignedNames.join(', ')}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            ...assignables.map(
              (a) => CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(a.$2),
                value: item.assignedUserIds.contains(a.$1),
                onChanged: (_) => _toggleAssignment(item, a.$1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String? step,
    required String title,
    String? hint,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (step != null)
            Text(step.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Theme.of(context).colorScheme.primary)),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (hint != null)
            Text(hint, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Detail of one split session: items, assignments and payment status.
class SplitDetailScreen extends StatefulWidget {
  const SplitDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SplitDetailScreen> createState() => _SplitDetailScreenState();
}

class _SplitDetailScreenState extends State<SplitDetailScreen> {
  _SplitSession? _session;
  List<_DetailItem> _items = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canDelete {
    final s = _session;
    if (s == null) return false;
    // Deletable only while nothing has been sent to anyone.
    return s.participants.where((p) => !p.isCreator).every((p) => p.requestStatus == null);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete split'),
        content: const Text(
            'Delete this split? No requests have been sent, so nothing else is affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await ApiClient.instance.dio.delete('/split/${widget.sessionId}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Split deleted')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          backgroundColor: Colors.red.shade300,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _sendRequests(String? userId) async {
    try {
      final res = await ApiClient.instance.dio
          .post('/split/${widget.sessionId}/requests/send', data: {
        if (userId != null) 'userIds': [userId],
      });
      if (!mounted) return;
      final sent = res.data['sent'] as int? ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sent > 0
              ? 'Request sent to $sent ${sent == 1 ? 'person' : 'people'}'
              : 'All requests were already sent')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          backgroundColor: Colors.red.shade300,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/split/${widget.sessionId}');
      if (!mounted) return;
      final j = res.data as Map<String, dynamic>;
      setState(() {
        _session = _SplitSession.fromJson(j);
        _items = ((j['items'] as List?) ?? const [])
            .map((e) => _DetailItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
        _loadFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          behavior: SnackBarBehavior.floating));
    }
  }

  String _money(int cents) {
    final d = cents ~/ 100;
    final r = (cents % 100).abs().toString().padLeft(2, '0');
    return 'S\$$d.$r';
  }

  String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
          title: Text(session == null || session.title.isEmpty
              ? 'Split'
              : session.title),
          actions: [
            if (_canDelete && !_deleting)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete split',
                onPressed: _delete,
              ),
          ]),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Could not load this split.',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : session == null
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                            child: Text('Could not load this split.',
                                style: TextStyle(color: Colors.grey))),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(session.title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16)),
                                    ),
                                    Text(
                                      _money(session.total),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_dateLabel(session.createdAt)} · ${session.status}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                ...session.participants.map(
                                  (p) {
                                    final label = p.isCreator ? 'You' : p.displayName;
                                    final chipLabel = p.isCreator
                                        ? 'YOU'
                                        : p.isZeroShare
                                            ? 'NOT INCLUDED'
                                            : switch (p.requestStatus) {
                                                'PAID' => 'PAID',
                                                'DECLINED' => 'DECLINED',
                                                'CANCELLED' => 'CANCELLED',
                                                'PENDING' => 'PENDING',
                                                _ => 'PENDING',
                                              };
                                    final declined = p.requestStatus ==
                                            'DECLINED' ||
                                        p.requestStatus == 'CANCELLED';
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: p.isCreator
                                                ? const Color(0xFFDCE9F7)
                                                : const Color(0xFFE8F0F8),
                                            child: Text(
                                              p.displayName.isEmpty
                                                  ? '?'
                                                  : p.displayName[0]
                                                      .toUpperCase(),
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0F4C81)),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(label,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                          Text(_money(p.shareAmount),
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          const SizedBox(width: 10),
                                          _StatusChip(
                                              label: chipLabel,
                                              paid: p.isPaid,
                                              neutral: p.isZeroShare,
                                              danger: declined),
                                          if (p.needsRequest) ...[
                                            const SizedBox(width: 8),
                                            OutlinedButton(
                                              onPressed: () => _sendRequests(
                                                  p.userId),
                                              style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10),
                                                  minimumSize:
                                                      const Size(0, 36)),
                                              child: const Text('Request',
                                                  style: TextStyle(
                                                      fontSize: 12)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                // Send-all sits AFTER the people list.
                                if (session.participants
                                    .any((p) => p.needsRequest))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: FilledButton.icon(
                                      onPressed: () => _sendRequests(null),
                                      style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF4A90D9),
                                          minimumSize:
                                              const Size.fromHeight(46)),
                                      icon: const Icon(Icons.send_outlined),
                                      label: const Text(
                                          'Send requests to everyone'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text('Items',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        const Text('No items.',
                            style: TextStyle(color: Colors.grey))
                      else
                        ..._items.map(
                          (item) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(item.name),
                              subtitle: Text(
                                item.assignedUserIds.isEmpty
                                    ? 'Split equally among everyone'
                                    : _namesFor(item.assignedUserIds,
                                        session.participants),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              trailing: Text(
                                _money(item.priceMinor),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
              ),
      ),
    );
  }

  String _namesFor(
      List<String> userIds, List<_SplitParticipant> participants) {
    final names = participants
        .where((p) => userIds.contains(p.userId))
        .map((p) => p.displayName)
        .toList();
    return names.isEmpty ? 'Unassigned' : names.join(', ');
  }
}

class _DetailItem {
  _DetailItem({
    required this.name,
    required this.priceMinor,
    required this.assignedUserIds,
  });

  factory _DetailItem.fromJson(Map<String, dynamic> j) => _DetailItem(
        name: '${j['name'] ?? ''}',
        priceMinor: int.tryParse('${j['priceMinor']}') ?? 0,
        assignedUserIds: ((j['assignedUserIds'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
      );

  final String name;
  final int priceMinor;
  final List<String> assignedUserIds;
}
