import 'package:flutter/material.dart';
import 'package:minipay/api/api_client.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/notifications');
      if (!mounted) return;
      setState(() {
        _items = (res.data as List).cast<Map<String, dynamic>>();
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

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['read'] == true) return;
    try {
      await ApiClient.instance.dio.post('/notifications/${n['id']}/read');
      _load();
    } catch (_) {}
  }

  Future<void> _markAll() async {
    try {
      await ApiClient.instance.dio.post('/notifications/read-all');
      _load();
    } catch (_) {}
  }

  IconData _icon(String type) {
    switch (type) {
      case 'TRANSFER_RECEIVED':
        return Icons.arrow_downward;
      case 'TRANSFER_SENT':
        return Icons.arrow_upward;
      case 'DEPOSIT_COMPLETED':
        return Icons.savings;
      case 'REQUEST_RECEIVED':
        return Icons.request_page;
      case 'REQUEST_PAID':
        return Icons.task_alt;
      case 'REQUEST_DECLINED':
        return Icons.do_not_disturb_on;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markAll,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text('Nothing here yet.',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final n = _items[i];
                      final unread = n['read'] != true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: unread ? Colors.white : Colors.grey.shade50,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: unread
                                ? Theme.of(ctx).colorScheme.primaryContainer
                                : Colors.grey.shade200,
                            child: Icon(_icon(n['type'] as String),
                                size: 20,
                                color: unread
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Colors.grey),
                          ),
                          title: Text(n['title'] as String,
                              style: TextStyle(
                                  fontWeight: unread
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          subtitle: Text(n['body'] as String),
                          trailing: unread
                              ? const Icon(Icons.circle,
                                  size: 10, color: Colors.redAccent)
                              : null,
                          onTap: () => _open(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
