import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:minipay/api/api_client.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late int _year;
  late int _month;
  Map<String, dynamic>? _report;
  bool _loading = true;
  DateTime? _accountCreated;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
    _loadAccountCreated();
  }

  Future<void> _loadAccountCreated() async {
    try {
      final res = await ApiClient.instance.dio.get('/auth/me');
      if (!mounted) return;
      final created = DateTime.tryParse(res.data['createdAt'] as String);
      if (created != null) {
        setState(() => _accountCreated = created);
        // If the selected month predates the account, jump to that month.
        if (_year < created.year ||
            (_year == created.year && _month < created.month)) {
          setState(() {
            _year = created.year;
            _month = created.month;
          });
          _load();
        }
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.dio.get('/wallet/report',
          queryParameters: {'year': _year, 'month': _month});
      if (!mounted) return;
      setState(() {
        _report = res.data as Map<String, dynamic>;
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

  /// One month before the account existed is viewable (shows an empty-state);
  /// anything earlier is blocked.
  DateTime? get _lowerBound {
    final c = _accountCreated;
    if (c == null) return null;
    return DateTime(c.year, c.month - 1);
  }

  bool get _preAccount {
    final c = _accountCreated;
    if (c == null) return false;
    return DateTime(_year, _month).isBefore(DateTime(c.year, c.month));
  }

  bool get _atLowerBound {
    final lower = _lowerBound;
    if (lower == null) return false;
    return DateTime(_year, _month) == lower;
  }

  void _shiftMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    if (m > 12) {
      m = 1;
      y += 1;
    }
    final candidate = DateTime(y, m);
    if (candidate.isAfter(DateTime.now().add(const Duration(days: 31)))) {
      return;
    }
    final lower = _lowerBound;
    if (lower != null && candidate.isBefore(lower)) return;
    setState(() {
      _year = y;
      _month = m;
    });
    _load();
  }

  int _minor(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;
  String _fmt(dynamic minor) {
    final cents = _minor(minor);
    final d = cents ~/ 100;
    final r = (cents % 100).abs().toString().padLeft(2, '0');
    return '${cents < 0 ? '-' : ''}\$$d.$r';
  }

  @override
  Widget build(BuildContext context) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final daily = (_report?['daily'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final byType = (_report?['byType'] as Map<String, dynamic>?) ?? {};

    return Scaffold(
      appBar: AppBar(
        // Title + compact month pill side by side; FittedBox guarantees
        // the row scales down instead of ever overflowing.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Monthly report'),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withAlpha(120),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _atLowerBound
                        ? const SizedBox(width: 34)
                        : IconButton(
                            onPressed: () => _shiftMonth(-1),
                            icon: const Icon(Icons.chevron_left, size: 20),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                    Text('${months[_month - 1]} $_year',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _preAccount
              ? SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              const Icon(Icons.history_toggle_off,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                  'No MiniPay activity in ${months[_month - 1]} $_year',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(
                                'Your account was created in ${months[_accountCreated!.month - 1]} ${_accountCreated!.year}. '
                                'Reports are available from that month onwards.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : SafeArea(
              top: false,
              child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _summaryCard('Money in', _fmt(_report?['totals']?['inflow']),
                          Colors.green, Icons.arrow_downward),
                      const SizedBox(width: 12),
                      _summaryCard('Money out', _fmt(_report?['totals']?['outflow']),
                          Colors.red, Icons.arrow_upward),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text('Net',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(
                            _fmt(_report?['totals']?['net']),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _minor(_report?['totals']?['net']) >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
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
                          Text('Daily flow',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          LegendDot(
                              color: Colors.green, label: 'Money in'),
                          LegendDot(color: Colors.red, label: 'Money out'),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 220,
                            child: daily.isEmpty
                                ? const Center(
                                    child: Text('No data',
                                        style:
                                            TextStyle(color: Colors.grey)))
                                : BarChart(
                                    BarChartData(
                                      gridData: const FlGridData(show: false),
                                      titlesData: FlTitlesData(
                                        topTitles: const AxisTitles(
                                            sideTitles:
                                                SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(
                                            sideTitles:
                                                SideTitles(showTitles: false)),
                                        leftTitles: const AxisTitles(
                                            sideTitles:
                                                SideTitles(showTitles: false)),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            interval: daily.length > 20 ? 5 : 3,
                                            getTitlesWidget: (v, meta) =>
                                                Text(
                                                    v.toInt() % 5 == 0
                                                        ? '${v.toInt()}'
                                                        : '',
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: Colors.grey)),
                                          ),
                                        ),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: daily
                                          .where((d) =>
                                              _minor(d['inflow']) > 0 ||
                                              _minor(d['outflow']) > 0)
                                          .map((d) {
                                        final day = d['day'] as int;
                                        return BarChartGroupData(
                                          x: day,
                                          barRods: [
                                            BarChartRodData(
                                              toY: _minor(d['inflow']) / 100,
                                              color: Colors.green,
                                              width: 6,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                            BarChartRodData(
                                              toY: _minor(d['outflow']) / 100,
                                              color: Colors.red,
                                              width: 6,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
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
                          Text('By category',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          if (byType.isEmpty)
                            const Text('No completed transactions this month.',
                                style: TextStyle(color: Colors.grey))
                          else
                            ...byType.entries.map((e) {
                              final label = switch (e.key) {
                                'DEPOSIT' => 'Card deposits',
                                'TRANSFER' => 'Transfers',
                                'MERCHANT_PAYMENT' => 'Merchant payments',
                                'REQUEST_PAYMENT' => 'Request payments',
                                _ => e.key,
                              };
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(label)),
                                    Text(
                                        'in ${_fmt(e.value['inflow'])}  ·  out ${_fmt(e.value['outflow'])}',
                                        style: const TextStyle(
                                            color: Colors.grey)),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
