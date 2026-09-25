import 'dart:async';

import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

const _filters = [
  ('ALL', 'All'),
  ('DEPOSIT', 'Deposits'),
  ('TRANSFER', 'Transfers'),
  ('MERCHANT_PAYMENT', 'Payments'),
  ('REQUEST_PAYMENT', 'Requests'),
];

class _HistoryScreenState extends State<HistoryScreen> {
  String _type = 'ALL';
  int? _year;
  int? _month;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  DateTime? _accountCreated;
  final _items = <Map<String, dynamic>>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

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
      final res = await ApiClient.instance.dio.get('/wallet/history',
          queryParameters: {
            'type': _type,
            'skip': skip,
            'take': 20,
            if (_searchCtrl.text.trim().isNotEmpty) 'q': _searchCtrl.text.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(apiError(e).message),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final firstAllowed = _accountCreated ?? DateTime(now.year - 3);
    final picked = await showDatePicker(
      context: context,
      initialDate: _year != null && _month != null
          ? DateTime(_year!, _month!)
          : now,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
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
                  hintText: 'Search by name',
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
                children: _filters.map((f) {
                  final selected = _type == f.$1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _type = f.$1);
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
                        child: Text('No transactions found.',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i >= _items.length) {
                            // Load-more row.
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
                                      style: TextStyle(color: Colors.grey))),
                            );
                          }
                          final t = _items[i];
                          return _txTile(t);
                        },
                      ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _txTile(Map<String, dynamic> t) {
    final isIn = t['direction'] == 'IN';
    final cents = int.tryParse(t['amount'] as String) ?? 0;
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    final status = t['status'] as String;
    final completed = status == 'COMPLETED';
    final cpty = t['counterparty'] as String?;
    final typeLabel = switch (t['type']) {
      'DEPOSIT' => 'Card deposit',
      'TRANSFER' => 'Transfer${cpty != null ? ' · $cpty' : ''}',
      'MERCHANT_PAYMENT' => 'Merchant payment${cpty != null ? ' · $cpty' : ''}',
      'REQUEST_PAYMENT' => 'Request payment${cpty != null ? ' · $cpty' : ''}',
      _ => t['type'] as String,
    };
    final date = DateTime.tryParse(t['createdAt'] as String)?.toLocal();
    final dateStr = date == null
        ? ''
        : '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: !completed
              ? Colors.grey.shade200
              : isIn
                  ? Colors.green.shade50
                  : Colors.red.shade50,
          child: Icon(
            isIn ? Icons.arrow_downward : Icons.arrow_upward,
            size: 20,
            color: !completed
                ? Colors.grey
                : isIn
                    ? Colors.green
                    : Colors.red,
          ),
        ),
        title: Text(typeLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(completed ? dateStr : status),
        trailing: Text(
          '${isIn ? '+' : '-'}\$$dollars.$rem',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: completed
                ? (isIn ? Colors.green : Colors.red)
                : Colors.grey,
          ),
        ),
      ),
    );
  }
}
