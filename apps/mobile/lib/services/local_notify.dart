import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:minipay/api/api_client.dart';

/// System notifications while the app is open (PGW-25). Android 13+ requires
/// a runtime permission request — done on first show.
class LocalNotify {
  LocalNotify._();
  static final LocalNotify instance = LocalNotify._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _idSeq = 1;

  Future<void> _init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        const InitializationSettings(android: android));
    _initialized = true;
  }

  Future<void> show({required String title, required String body}) async {
    await _init();
    final android = AndroidNotificationDetails(
      'money_events',
      'Money events',
      channelDescription: 'Payments, sales, refunds and account updates',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      _idSeq++,
      title,
      body,
      NotificationDetails(android: android),
    );
    // Android 13+ permission (no-op on older versions).
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Fetches server notifications and surfaces any new unread ones as system
  /// notifications. Called by the home screens' poll; never throws.
  Future<void> syncFromServer() async {
    try {
      final res = await ApiClient.instance.dio.get('/notifications');
      final list = (res.data as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final cursor = await ApiClient.instance.readNotifCursor();
      final cursorDt = DateTime.tryParse(cursor ?? '');
      DateTime? newestDt;
      for (final n in list) {
        final createdAt = DateTime.tryParse(n['createdAt'] as String? ?? '');
        if (createdAt == null) continue;
        if (cursorDt != null && !createdAt.isAfter(cursorDt)) continue;
        if (n['read'] == true) continue; // already seen in-app
        await show(
          title: n['title'] as String? ?? 'MiniPay',
          body: n['body'] as String? ?? '',
        );
        if (newestDt == null || createdAt.isAfter(newestDt)) newestDt = createdAt;
      }
      if (newestDt != null) {
        await ApiClient.instance.saveNotifCursor(newestDt.toUtc().toIso8601String());
      }
    } catch (_) {
      // Notifications are best-effort; never break the poll.
    }
  }
}
