import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';

/// Full sales page (PGW-20): search, status filters, month picker, sort and
/// load-more — mirroring the normal user history screen.
class MerchantSalesScreen extends StatefulWidget {
  const MerchantSalesScreen({super.key});

  @override
  State<MerchantSalesScreen> createState() => _MerchantSalesScreenState();
}

const _statusFilters = [
  ('ALL', 'All'),
  ('PAID', 'Paid'),
  ('PENDING', 'Pending'),
  ('REFUNDED', 'Refunded'),
];

const _sortOptions = [
  ('newest', 'Newest first'),
  ('oldest', 'Oldest first'),
  ('amount_high', 'Amount: high to low'),
  ('amount_low', 'Amount: low to high'),
];

class _MerchantSalesScreenState extends State<MerchantSalesScreen> {
  String _status = 'ALL';
  String _sort = 'newest';
  int? _year;
  int? _month;
  DateTime? _accountCreated;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  final _items = <Map<String, dynamic>>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refundingId = false;

  @override
  void initState() {
    super.initState();
    _loadAccountCreated();
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccountCreated() async {
    try {
      final res = await ApiClient.instance.dio.get('/auth/me');
      if (!mounted) return;
      final created = DateTime.tryParse(res.data['createdAt'] as String);
      if (created != null) setState(() => _accountCreated = created);
    } catch (_) {}
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _reload();
    });
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _loading = true;
    });
    await _fetchMore(reset: true);
  }

  Future<void> _fetchMore({bool reset = false}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final skip = reset ? 0 : _items.length;
      final res = await ApiClient.instance.dio.get('/merchants/mine/sales',
          queryParameters: {
            'skip': skip,
            'take': 20,
            'sort': _sort,
            'status': _status,
            if (_searchCtrl.text.trim().isNotEmpty)
              'q': _searchCtrl.text.trim(),
            if (_year != null && _month != null) 'year': _year,
            if (_year != null && _month != null) 'month': _month,
          });
      if (!mounted) return;
      final page = (res.data['items'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _total = res.data['total'] as int;
        if (reset) _items.clear();
        _items.addAll(page);
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load sales'),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final firstAllowed = _accountCreated ?? DateTime(now.year - 3);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _year != null && _month != null ? DateTime(_year!, _month!) : now,
      firstDate: firstAllowed,
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _year = picked.year;
        _month = picked.month;
      });
      _reload();
    }
  }

  String get _monthLabel =>
      _year != null && _month != null ? '$_month/$_year' : 'All time';

  Future<void> _refundSale(Map<String, dynamic> sale) async {
    final cents = int.tryParse(sale['amountMinor'] as String) ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund this sale?'),
        content: Text(
            'The full amount of S${(cents / 100).toStringAsFixed(2)} will be '
            'returned to the customer\'s wallet. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828)),
              child: const Text('Refund')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _refundingId = true);
    try {
      await ApiClient.instance.dio
          .post('/merchants/mine/sales/${sale['id']}/refund');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sale refunded to the customer\'s wallet')));
      await _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data is Map &&
              (e.response!.data as Map)['message'] != null
          ? (e.response!.data as Map)['message'].toString()
          : 'Refund failed';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refund failed')));
    } finally {
      if (mounted) setState(() => _refundingId = false);
    }
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
              if (sale['status'] == 'PAID')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _refundingId ? null : () => _refundSale(sale),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFC62828)),
                    icon: _refundingId
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.undo),
                    label: Text(_refundingId
                        ? 'Refunding…'
                        : 'Refund to customer'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              setState(() => _sort = v);
              _reload();
            },
            itemBuilder: (_) => _sortOptions
                .map((o) => CheckedPopupMenuItem(
                      value: o.$1,
                      checked: _sort == o.$1,
                      child: Text(o.$2),
                    ))
                .toList(),
          ),
          TextButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text(_monthLabel),
          ),
          if (_year != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              tooltip: 'Clear month filter',
              onPressed: () {
                setState(() {
                  _year = null;
                  _month = null;
                });
                _reload();
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by order ref or note',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _reload();
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _statusFilters.map((f) {
                  final selected = _status == f.$1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _status = f.$1);
                        _reload();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(
                          child: Text('No sales found.',
                              style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length + 1,
                          itemBuilder: (ctx, i) {
                            if (i >= _items.length) {
                              if (_items.length < _total) {
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: OutlinedButton(
                                    onPressed: _loadingMore
                                        ? null
                                        : () => _fetchMore(),
                                    child: Text(_loadingMore
                                        ? 'Loading…'
                                        : 'Load more'),
                                  ),
                                );
                              }
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: Text('End of list',
                                        style: TextStyle(
                                            color: Colors.grey))),
                              );
                            }
                            return saleTile(_items[i], _showSaleDetails);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared: formatted sale date.
String saleDateLabel(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Shared: detail-sheet row.
Widget saleDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 110,
            child:
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13))),
      ],
    ),
  );
}

/// Shared: sale list tile.
Widget saleTile(Map<String, dynamic> s, void Function(Map<String, dynamic>) onTap) {
  final status = s['status'] as String;
  final refunded = status == 'REFUNDED';
  final paid = status == 'PAID';
  final cents = int.tryParse(s['amountMinor'] as String) ?? 0;
  final dollars = cents ~/ 100;
  final rem = (cents % 100).abs().toString().padLeft(2, '0');
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: refunded
            ? Colors.grey.shade200
            : paid
                ? Colors.green.shade50
                : Colors.orange.shade50,
        child: Icon(
          refunded
              ? Icons.undo
              : paid
                  ? Icons.shopping_bag
                  : Icons.hourglass_top,
          color: refunded
              ? Colors.grey.shade600
              : paid
                  ? Colors.green
                  : Colors.orange.shade700,
        ),
      ),
      title: Text(
          s['description'] as String? ?? s['orderRef'] as String? ?? 'Sale',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(refunded
          ? 'Refunded · ${saleDateLabel(s['createdAt'] as String?)}'
          : paid
              ? 'Paid · ${saleDateLabel(s['paidAt'] as String? ?? s['createdAt'] as String?)}'
              : status),
      trailing: Text(
        refunded ? '-\$$dollars.$rem' : '+\$$dollars.$rem',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: refunded
              ? Colors.grey
              : paid
                  ? Colors.green
                  : Colors.grey,
        ),
      ),
      onTap: () => onTap(s),
    ),
  );
}
