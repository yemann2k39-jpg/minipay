import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:minipay/api/api_client.dart';
import 'package:fl_chart/fl_chart.dart';

/// Merchant sales insights (PGW-27): today/week summaries + 7-day chart.
class MerchantInsightsScreen extends StatefulWidget {
  const MerchantInsightsScreen({super.key});

  @override
  State<MerchantInsightsScreen> createState() => _MerchantInsightsScreenState();
}

class _MerchantInsightsScreenState extends State<MerchantInsightsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/merchants/mine/insights');
      if (!mounted) return;
      setState(() {
        _data = res.data as Map<String, dynamic>;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.response?.data is Map &&
              (e.response!.data as Map)['message'] != null
          ? (e.response!.data as Map)['message'].toString()
          : 'Could not load insights';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(String minor) {
    final cents = int.tryParse(minor) ?? 0;
    final dollars = cents ~/ 100;
    final rem = (cents % 100).abs().toString().padLeft(2, '0');
    return '\$$dollars.$rem';
  }

  @override
  Widget build(BuildContext context) {
    final purple = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Sales insights')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _summaryCard(
                            context,
                            'Today',
                            _fmt(_data?['todayTotalMinor'] as String? ?? '0'),
                            '${_data?['todayCount'] ?? 0} sales',
                            const Color(0xFF0F4C81),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _summaryCard(
                            context,
                            'Last 7 days',
                            _fmt(_data?['weekTotalMinor'] as String? ?? '0'),
                            '${_data?['weekCount'] ?? 0} sales',
                            purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if ((int.tryParse(
                                _data?['refundedWeekMinor'] as String? ?? '0') ??
                            0) >
                        0)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Refunded this week: ${_fmt(_data?['refundedWeekMinor'] as String? ?? '0')}',
                          style: TextStyle(color: Colors.orange.shade900),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sales — last 7 days',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 200,
                              child: _chart(context),
                            ),
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

  Widget _chart(BuildContext context) {
    final days = (_data?['days'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final maxY = days.fold<double>(
        1, (m, d) => m > (int.tryParse(d['totalMinor'] as String? ?? '0') ?? 0) / 100 ? m : (int.tryParse(d['totalMinor'] as String? ?? '0') ?? 0) / 100);
    return BarChart(
      BarChartData(
        maxY: maxY * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= days.length) return const SizedBox();
                final date = DateTime.parse(days[idx]['date'] as String);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${date.day}/${date.month}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(days.length, (i) {
          final total =
              (int.tryParse(days[i]['totalMinor'] as String? ?? '0') ?? 0) / 100;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: total,
                width: 18,
                color: total > 0
                    ? const Color(0xFF0F4C81)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              'S\$${rod.toY.toStringAsFixed(2)}\n${days[gi]['count']} sales',
              const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(
      BuildContext context, String label, String amount, String sub, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text(amount,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(sub,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
