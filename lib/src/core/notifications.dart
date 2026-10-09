import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_schedule.dart';

class ReminderDeepLink {
  const ReminderDeepLink(this.type, this.entityId);
  final FinanceReminderType type;
  final int entityId;
}

@pragma('vm:entry-point')
void finKeepReminderBackgroundTap(NotificationResponse response) {
  if (response.actionId == 'snooze') {
    unawaited(LocalReminderService().snooze(response.payload));
  }
}

class LocalReminderService {
  LocalReminderService();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _platform = MethodChannel('finkeep/reminders');
  static bool _ready = false;
  static Future<void>? _initializing;
  static void Function(ReminderDeepLink)? _onOpen;

  void setOpenHandler(void Function(ReminderDeepLink)? handler) {
    _onOpen = handler;
  }

  Future<void> initialize() async {
    if (_ready) return;
    if (_initializing != null) return _initializing;
    final task = _initialize();
    _initializing = task;
    try {
      await task;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    try {
      final name = await _platform.invokeMethod<String>('timeZone');
      if (name != null) tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // UTC still preserves the instant derived from local DateTime.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: finKeepReminderBackgroundTap,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      for (final (id, name) in [
        ('finkeep_emis', 'EMIs'),
        ('finkeep_money', 'Money'),
        ('finkeep_subscriptions', 'Subscriptions'),
      ]) {
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            id,
            name,
            description: 'FinKeep local $name reminders',
            importance: Importance.high,
          ),
        );
      }
    }
    _ready = true;
  }

  Future<bool> permissionGranted() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
  }

  Future<void> openPermissionSettings() =>
      _platform.invokeMethod<void>('openNotificationSettings');

  Future<void> openBatterySettings() =>
      _platform.invokeMethod<void>('openBatterySettings');

  static void _handleResponse(NotificationResponse response) {
    if (response.actionId == 'snooze') {
      unawaited(LocalReminderService().snooze(response.payload));
      return;
    }
    final link = _decodeLink(response.payload);
    if (link != null) _onOpen?.call(link);
  }

  Future<ReminderDeepLink?> launchLink() async {
    await initialize();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? _decodeLink(launch?.notificationResponse?.payload)
        : null;
  }

  static ReminderDeepLink? _decodeLink(String? payload) {
    if (payload == null || !payload.startsWith('finkeep:')) return null;
    try {
      final data = jsonDecode(payload.substring(8)) as Map<String, dynamic>;
      final type = FinanceReminderType.values.firstWhere(
        (item) => item.name == data['type'],
      );
      final id = data['id'];
      return id is int ? ReminderDeepLink(type, id) : null;
    } catch (_) {
      return null;
    }
  }

  static String payloadFor(ReminderTarget target) =>
      'finkeep:${jsonEncode({'type': target.type.name, 'id': target.entityId, 'name': target.name, 'due': target.dueDate.toIso8601String()})}';

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    FinanceReminderType type = FinanceReminderType.money,
    String? payload,
    bool repeatDaily = false,
  }) async {
    await initialize();
    if (!when.isAfter(DateTime.now())) return;
    final (channelId, channelName) = switch (type) {
      FinanceReminderType.emi => ('finkeep_emis', 'EMIs'),
      FinanceReminderType.money => ('finkeep_money', 'Money'),
      FinanceReminderType.subscription => (
        'finkeep_subscriptions',
        'Subscriptions',
      ),
    };
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.secret,
          actions: payload == null
              ? const []
              : const [
                  AndroidNotificationAction('snooze', 'Snooze until tomorrow'),
                ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
    );
  }

  Future<void> replaceManaged(Iterable<int> desiredIds) async {
    await initialize();
    final desired = desiredIds.toSet();
    final pending = await _plugin.pendingNotificationRequests();
    for (final item in pending) {
      if (item.id >= 1100000000 &&
          item.id < 1600000000 &&
          item.payload?.startsWith('finkeep:') == true &&
          !desired.contains(item.id)) {
        await _plugin.cancel(id: item.id);
      }
    }
  }

  Future<void> clearLegacySubscriptionReminders() async {
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final item in pending) {
      if (item.id >= 1000000 &&
          item.id < 100000000 &&
          item.payload == null &&
          (item.title?.contains('renews in') == true ||
              item.title?.contains('trial ends') == true ||
              item.title?.contains('resumes soon') == true)) {
        await _plugin.cancel(id: item.id);
      }
    }
  }

  Future<void> showTest() async {
    await initialize();
    await _plugin.show(
      id: 1999999998,
      title: 'FinKeep test reminder',
      body: 'Local reminders are ready on this phone.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'finkeep_money',
          'Money',
          visibility: NotificationVisibility.secret,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> snooze(String? payload) async {
    final link = _decodeLink(payload);
    if (link == null) return;
    final data = jsonDecode(payload!.substring(8)) as Map<String, dynamic>;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final name = data['name'] is String ? data['name'] as String : 'Payment';
    await scheduleReminder(
      id:
          1600000000 +
          (link.entityId * 31 + tomorrow.day + link.type.index) % 300000000,
      title: '$name reminder',
      body: 'A payment is due. Open FinKeep for details.',
      when: tomorrow,
      type: link.type,
      payload: payload,
    );
  }

  Future<void> cancelReminder(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }
}
