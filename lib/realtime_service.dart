import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'app_config.dart';

class LiveTelemetry {
  final int machineId;
  final String machineName;
  final String readingType;
  final double value;
  final String unit;
  final String? recordedAt;
  LiveTelemetry({required this.machineId, required this.machineName, required this.readingType, required this.value, required this.unit, this.recordedAt});
}

class WorkforceRealtime {
  final String apiBaseUrl, supabaseUrl, supabasePublishableKey;
  final StreamController<LiveTelemetry> _controller = StreamController<LiveTelemetry>.broadcast();
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _stopped = false;

  WorkforceRealtime({required this.apiBaseUrl, required this.supabaseUrl, required this.supabasePublishableKey});
  Stream<LiveTelemetry> get telemetry => _controller.stream;

  Future<void> start() async { _stopped = false; await _connect(); }

  Future<void> stop() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> _connect() async {
    if (_stopped || supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('worker_access_token');
      if (token == null || token.isEmpty) return;
      final headers = <String, String>{
        'Authorization': 'Bearer ' + token,
        'X-Maintain-Application': maintainApplication,
        'Content-Type': 'application/json',
      };
      final response = await http.post(Uri.parse(apiBaseUrl + '/api/auth/realtime-token'), headers: headers, body: '{}').timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Realtime authorization failed');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final realtimeToken = data['access_token']?.toString();
      if (realtimeToken == null || realtimeToken.isEmpty) throw Exception('Realtime token missing');

      final meResponse = await http.get(Uri.parse(apiBaseUrl + '/api/auth/me'), headers: headers).timeout(const Duration(seconds: 10));
      if (meResponse.statusCode < 200 || meResponse.statusCode >= 300) throw Exception('Unable to resolve organization');
      final me = jsonDecode(meResponse.body) as Map<String, dynamic>;
      final org = me['organization_id'];
      if (org == null) throw Exception('Organization missing');

      final base = supabaseUrl.replaceFirst(RegExp(r'^http'), 'ws').replaceFirst(RegExp(r'/$'), '');
      final wsUri = Uri.parse(base + '/realtime/v1/websocket?apikey=' + Uri.encodeQueryComponent(supabasePublishableKey) + '&vsn=1.0.0');
      final channel = WebSocketChannel.connect(wsUri);
      _channel = channel;
      _attempt = 0;
      final topic = 'realtime:org:' + org.toString() + ':telemetry';
      channel.sink.add(jsonEncode(<dynamic>[
        '1', '1', topic, 'phx_join',
        <String, dynamic>{
          'config': <String, dynamic>{'broadcast': <String, dynamic>{'self': false}, 'private': true},
          'access_token': realtimeToken,
        },
      ]));

      channel.stream.listen(_handleMessage, onError: (_) => _scheduleReconnect(), onDone: _scheduleReconnect, cancelOnError: true);
      Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_stopped || _channel != channel) { timer.cancel(); return; }
        try {
          channel.sink.add(jsonEncode(<dynamic>[DateTime.now().millisecondsSinceEpoch.toString(), '2', 'phoenix', 'heartbeat', <String, dynamic>{}]));
        } catch (_) { timer.cancel(); }
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw.toString());
      if (msg is! Map || msg['event'] != 'broadcast') return;
      final outer = msg['payload'];
      final payload = outer is Map && outer['payload'] is Map
          ? Map<String, dynamic>.from(outer['payload'] as Map)
          : outer is Map ? Map<String, dynamic>.from(outer) : null;
      if (payload == null || payload['type'] != 'telemetry') return;
      final value = double.tryParse(payload['value'].toString());
      final machineId = int.tryParse(payload['machine_id'].toString());
      if (value == null || machineId == null) return;
      _controller.add(LiveTelemetry(
        machineId: machineId,
        machineName: payload['machine']?.toString() ?? 'Machine',
        readingType: payload['reading_type']?.toString() ?? 'sensor',
        value: value,
        unit: payload['unit']?.toString() ?? '',
        recordedAt: payload['recorded_at']?.toString(),
      ));
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_stopped || _reconnectTimer != null) return;
    final seconds = math.min(30, 1 << math.min(_attempt, 5));
    _attempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () { _reconnectTimer = null; _connect(); });
  }

  Future<void> dispose() async { await stop(); await _controller.close(); }
}
