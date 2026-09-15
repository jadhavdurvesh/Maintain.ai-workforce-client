import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _notificationApiBaseUrl = 'https://maintain-ai-3.vercel.app';
const String _deviceTokenKey = 'maintain_ai_fcm_token';
const String _workerUsernameKey = 'maintain_ai_notification_worker';

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> maintainAiFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized by the platform.
  }
}

class NotificationService {
  static bool _ready = false;
  static bool _firebaseAvailable = false;
  static String? _workerUsername;

  static Future<void> initialize() async {
    if (_ready) return;
    _ready = true;

    try {
      await Firebase.initializeApp();
      _firebaseAvailable = true;
      FirebaseMessaging.onBackgroundMessage(maintainAiFirebaseBackgroundHandler);

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );

      const channel = AndroidNotificationChannel(
        'maintain_ai_alerts',
        'MAINTAIN AI Alerts',
        description: 'Critical machines, faults and assigned maintenance work.',
        importance: Importance.max,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

      await _syncRegistration();
    } catch (_) {
      // The app remains fully usable when Firebase has not been configured yet.
      _firebaseAvailable = false;
    }
  }

  static Future<void> _syncRegistration() async {
    if (!_firebaseAvailable) return;
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('worker_access_token');
    if (accessToken == null || accessToken.isEmpty) return;

    try {
      final me = await http.get(
        Uri.parse('$_notificationApiBaseUrl/api/auth/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 10));
      if (me.statusCode < 200 || me.statusCode >= 300) return;

      final body = jsonDecode(me.body);
      final username = body is Map ? body['username']?.toString() : null;
      if (username == null || username.isEmpty) return;
      _workerUsername = username;
      await prefs.setString(_workerUsernameKey, username);

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerToken(token);
      }
    } catch (_) {
      // Registration will retry on the next app start or token refresh.
    }
  }

  static Future<void> _registerToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final username = _workerUsername ?? prefs.getString(_workerUsernameKey);
    final accessToken = prefs.getString('worker_access_token');
    if (username == null || username.isEmpty || accessToken == null || accessToken.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('$_notificationApiBaseUrl/api/notifications/register-device'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'worker_username': username,
          'device_token': token,
          'platform': 'android',
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await prefs.setString(_deviceTokenKey, token);
      }
    } catch (_) {}
  }

  static Future<void> unregister() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_deviceTokenKey);
    if (token != null && token.isNotEmpty) {
      try {
        await http.delete(
          Uri.parse('$_notificationApiBaseUrl/api/notifications/device?device_token=${Uri.encodeQueryComponent(token)}'),
          headers: {'Authorization': 'Bearer ${prefs.getString('worker_access_token') ?? ''}'},
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    await prefs.remove(_deviceTokenKey);
    await prefs.remove(_workerUsernameKey);
    _workerUsername = null;
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      message.hashCode,
      notification.title ?? 'MAINTAIN AI',
      notification.body ?? 'New maintenance notification',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'maintain_ai_alerts',
          'MAINTAIN AI Alerts',
          channelDescription: 'Critical machines, faults and assigned maintenance work.',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static void _handleOpenedMessage(RemoteMessage message) {
    // The notification payload contains the relevant work-order/fault/alert id.
    // The app will refresh its data when it resumes, so no stale record is shown.
  }

  static Future<void> openCenter(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final username = _workerUsername ?? prefs.getString(_workerUsernameKey);
    if (username == null || username.isEmpty) return;
    final token = prefs.getString('worker_access_token');
    if (token == null || token.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$_notificationApiBaseUrl/api/notifications?worker_username=${Uri.encodeQueryComponent(username)}'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final decoded = jsonDecode(response.body);
      final notifications = decoded is List ? decoded : <dynamic>[];
      if (!context.mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0B1728),
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Notifications', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
                      TextButton(
                        onPressed: () async {
                          await http.post(
                            Uri.parse('$_notificationApiBaseUrl/api/notifications/read-all?worker_username=${Uri.encodeQueryComponent(username)}'),
                            headers: {'Authorization': 'Bearer $token'},
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        child: const Text('Mark all read'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: notifications.isEmpty
                      ? const Center(child: Text('No notifications', style: TextStyle(color: Colors.white54)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: notifications.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final item = Map<String, dynamic>.from(notifications[index] as Map);
                            final read = item['read'] == true;
                            return Card(
                              color: read ? const Color(0xFF111D2E) : const Color(0xFF14263D),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: (read ? Colors.white38 : Colors.lightBlueAccent).withOpacity(.12),
                                  child: Icon(
                                    item['notification_type'] == 'critical_machine' || item['notification_type'] == 'critical_fault'
                                        ? Icons.warning_amber_rounded
                                        : Icons.notifications_active_outlined,
                                    color: read ? Colors.white54 : Colors.lightBlueAccent,
                                  ),
                                ),
                                title: Text(item['title']?.toString() ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(item['body']?.toString() ?? '', style: const TextStyle(color: Colors.white60)),
                                ),
                                onTap: () async {
                                  final id = item['id'];
                                  if (id != null && !read) {
                                    await http.post(
                                      Uri.parse('$_notificationApiBaseUrl/api/notifications/$id/read?worker_username=${Uri.encodeQueryComponent(username)}'),
                                      headers: {'Authorization': 'Bearer $token'},
                                    );
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {}
  }
}
