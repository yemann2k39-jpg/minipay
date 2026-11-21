import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:minipay/api/api_client.dart';
import 'package:share_plus/share_plus.dart';

/// Detail of one transaction, loaded from GET /wallet/transactions/:id.
class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  Map<String, dynamic>? _tx;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final res =
          await ApiClient.instance.dio.get('/wallet/transactions/${widget.transactionId}');
      if (!mounted) return;
      setState(() {
        _tx = res.data as Map<String, dynamic>;
        _loading = false;
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

  String _money(int cents) {
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    return 'S\$$dollars.$rem';
  }

  String _dateLabel(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _copyId(String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied'), behavior: SnackBarBehavior.floating));
  }

  /// Shareable text receipt (PGW-26).
  void _shareReceipt(Map<String, dynamic> t) {
    final isIn = t['direction'] == 'IN';
    final cents = int.tryParse('${t['amount']}') ?? 0;
    final counterparty = t['counterparty'] as String?;
    final buffer = StringBuffer()
      ..writeln('MiniPay receipt')
      ..writeln('----------------')
      ..writeln('${_typeLabel(t['type'] as String)}'
          ' (${isIn ? 'received' : 'sent'})')
      ..writeln('Amount: ${_money(cents)}')
      ..writeln('Status: ${t['status']}');
    if (counterparty != null && counterparty.isNotEmpty) {
      buffer.writeln('${isIn ? 'From' : 'To'}: $counterparty');
    }
    buffer
      ..writeln('Date: ${_dateLabel(t['createdAt'] as String)}')
      ..writeln('Ref: ${t['id'] ?? widget.transactionId}');
    SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (_tx != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share receipt',
              onPressed: () => _shareReceipt(_tx!),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed || _tx == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Could not load this transaction.',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildHeader(_tx!),
                        const SizedBox(height: 16),
                        _buildDetails(_tx!),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> t) {
    final isIn = t['direction'] == 'IN';
    final cents = int.tryParse('${t['amount']}') ?? 0;
    final status = t['status'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  isIn ? const Color(0xFFE5F6EC) : const Color(0xFFFDECEA),
              child: Icon(
                isIn ? Icons.arrow_downward : Icons.arrow_upward,
                size: 28,
                color: isIn ? const Color(0xFF1B7F4B) : const Color(0xFFC0392B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${isIn ? '+' : '−'}${_money(cents)}',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: isIn ? const Color(0xFF1B7F4B) : const Color(0xFFC0392B),
              ),
            ),
            const SizedBox(height: 12),
            _statusChip(status),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final (Color bg, Color border, Color fg) = switch (status) {
      'COMPLETED' => (
          const Color(0xFFE5F6EC),
          const Color(0xFFBFE6CF),
          const Color(0xFF1B7F4B),
        ),
      'PENDING' => (
          const Color(0xFFFDF1E0),
          const Color(0xFFF3D9AE),
          const Color(0xFFB26A00),
        ),
      _ => (
          const Color(0xFFFDECEA),
          const Color(0xFFF3C1BC),
          const Color(0xFFB71C1C),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(Map<String, dynamic> t) {
    final counterparty = t['counterparty'] as String?;
    final completedAt = t['completedAt'] as String?;
    final id = '${t['id'] ?? widget.transactionId}';
    final shortId = id.length <= 8 ? id : '${id.substring(0, 8)}…';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _detailRow('Type', _typeLabel(t['type'] as String)),
            const Divider(height: 1),
            if (counterparty != null && counterparty.isNotEmpty) ...[
              _detailRow(
                  t['direction'] == 'IN' ? 'From' : 'To', counterparty),
              const Divider(height: 1),
            ],
            _detailRow('Date created',
                _dateLabel(t['createdAt'] as String)),
            if (completedAt != null) ...[
              const Divider(height: 1),
              _detailRow('Date completed', _dateLabel(completedAt)),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Transaction ID',
                        style: TextStyle(color: Color(0xFF6B7280))),
                  ),
                  Text(shortId,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937))),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy transaction ID',
                    onPressed: () => _copyId(id),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
