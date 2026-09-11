import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiBaseUrl = 'https://maintain-ai-3.vercel.app';

void main() {
  runApp(const WorkforceApp());
}

class ApiClient {
  Future<dynamic> get(String path) async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl$path'))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    return jsonDecode(response.body);
  }

  Future<dynamic> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .patch(
          Uri.parse('$apiBaseUrl$path'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    return jsonDecode(response.body);
  }
}

class WorkforceApp extends StatelessWidget {
  const WorkforceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Industrial Workforce',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D8BFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF08111F),
        cardTheme: const CardTheme(
          color: Color(0xFF111D2E),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const WorkforceHome(),
    );
  }
}

class WorkforceHome extends StatefulWidget {
  const WorkforceHome({super.key});

  @override
  State<WorkforceHome> createState() => _WorkforceHomeState();
}

class _WorkforceHomeState extends State<WorkforceHome> {
  final ApiClient api = ApiClient();

  int selectedTab = 0;

  bool loading = true;
  bool demoMode = false;
  bool syncing = false;

  String? message;

  Timer? refreshTimer;

  List<Map<String, dynamic>> machines = [];
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> alerts = [];

  List<Map<String, dynamic>> previousOrders = [];
  List<Map<String, dynamic>> previousAlerts = [];

  @override
  void initState() {
    super.initState();

    refresh();

    refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refresh(silent: true),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> refresh({
    bool silent = false,
  }) async {
    if (syncing) {
      return;
    }

    syncing = true;

    if (!silent && mounted) {
      setState(() {
        loading = true;
        message = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        api.get('/api/machines'),
        api.get('/api/work-orders'),
        api.get('/api/alerts'),
      ]);

      if (!mounted) {
        return;
      }

      final nextMachines = _toMaps(results[0]);
      final nextOrders = _toMaps(results[1]);
      final nextAlerts = _toMaps(results[2]);

      final hasNewWorkOrder = nextOrders.any(
        (item) => !previousOrders.any(
          (old) => '${old['id']}' == '${item['id']}',
        ),
      );

      final hasNewAlert = nextAlerts.any(
        (item) => !previousAlerts.any(
          (old) => '${old['id']}' == '${item['id']}',
        ),
      );

      setState(() {
        machines = nextMachines;
        orders = nextOrders;
        alerts = nextAlerts;

        previousOrders =
            List<Map<String, dynamic>>.from(nextOrders);

        previousAlerts =
            List<Map<String, dynamic>>.from(nextAlerts);

        loading = false;
        demoMode = false;
        message = null;
      });

      if (silent && (hasNewWorkOrder || hasNewAlert)) {
        _showSnack(
          hasNewWorkOrder
              ? 'New work order received.'
              : 'New machine alert received.',
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;

        if (machines.isEmpty &&
            orders.isEmpty &&
            alerts.isEmpty) {
          machines = _demoMachines();
          orders = _demoOrders();
          alerts = _demoAlerts();

          previousOrders =
              List<Map<String, dynamic>>.from(orders);

          previousAlerts =
              List<Map<String, dynamic>>.from(alerts);

          demoMode = true;

          message =
              'Backend unavailable — demo data is shown.';
        } else {
          message =
              'Connection unavailable — showing last received data.';
        }
      });
    } finally {
      syncing = false;
    }
  }

  List<Map<String, dynamic>> _toMaps(dynamic value) {
    if (value is! List) {
      return <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  double _number(dynamic value) {
    return double.tryParse('$value') ?? 0;
  }

  Future<void> updateWorkOrder(
    Map<String, dynamic> order,
    String status, {
    String? notes,
  }) async {
    try {
      await api.patch(
        '/api/work-orders/${order['id']}',
        {
          'status': status,
          if (notes != null)
            'resolution_notes': notes,
        },
      );

      _showSnack('Work order updated.');

      await refresh(silent: true);
    } catch (error) {
      _showSnack(
        'Could not update work order: $error',
        error: true,
      );
    }
  }

  void _showSnack(
    String text, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFF7C2231)
            : const Color(0xFF17402C),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _dashboardPage(),
      _machinesPage(),
      _workOrdersPage(),
      _alertsPage(),
      _morePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Industrial Workforce',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(15),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          IconButton(
            onPressed: () => refresh(),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: pages[selectedTab],

      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.precision_manufacturing_outlined,
            ),
            selectedIcon: Icon(
              Icons.precision_manufacturing,
            ),
            label: 'Machines',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Work Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _dashboardPage() {
    final averageHealth = machines.isEmpty
        ? 0.0
        : machines
                .map(
                  (machine) =>
                      _number(machine['health_score']),
                )
                .reduce((a, b) => a + b) /
            machines.length;

    final openOrders = orders
        .where(
          (order) =>
              '${order['status']}'.toLowerCase() !=
              'completed',
        )
        .length;

    final activeAlerts = alerts
        .where(
          (alert) => alert['resolved'] != true,
        )
        .length;

    final criticalMachines = machines
        .where(
          (machine) =>
              _number(machine['health_score']) < 40,
        )
        .length;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (message != null)
            _statusBanner(message!),

          _heroCard(averageHealth),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _metricCard(
                  'Machines',
                  '${machines.length}',
                  Icons.precision_manufacturing,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  'Open Jobs',
                  '$openOrders',
                  Icons.assignment,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  'Alerts',
                  '$activeAlerts',
                  Icons.warning_amber,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          _wideMetricCard(
            'Critical machines',
            '$criticalMachines',
            Icons.warning_amber_rounded,
            criticalMachines > 0
                ? Colors.redAccent
                : Colors.greenAccent,
          ),

          const SizedBox(height: 22),

          _sectionHeader(
            'My Machines',
            'Current machine health',
          ),

          const SizedBox(height: 10),

          if (machines.isEmpty)
            _emptyState(
              'No machines',
              'No machine information is currently available.',
            )
          else
            ...machines.take(5).map(_machineTile),

          const SizedBox(height: 18),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Assigned Work',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    selectedTab = 2;
                  });
                },
                child: const Text('View all'),
              ),
            ],
          ),

          if (orders.isEmpty)
            _emptyState(
              'No work orders',
              'New assigned jobs will appear here.',
            )
          else
            ...orders.take(3).map(_orderPreview),
        ],
      ),
    );
  }

  Widget _heroCard(double averageHealth) {
    final color = averageHealth >= 70
        ? Colors.greenAccent
        : averageHealth >= 40
            ? Colors.amberAccent
            : Colors.redAccent;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Worker Dashboard',
                    style: TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    averageHealth == 0
                        ? '—'
                        : '${averageHealth.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const Text(
                    'Average machine health',
                    style: TextStyle(
                      color: Colors.white54,
                    ),
                  ),
                  if (demoMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Preview mode',
                        style: TextStyle(
                          color: Colors.amberAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 34,
              backgroundColor:
                  color.withOpacity(.12),
              child: Icon(
                Icons.engineering,
                size: 34,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _machinesPage() {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(
            'My Machines',
            'Machine status and health',
          ),

          const SizedBox(height: 16),

          if (machines.isEmpty)
            _emptyState(
              'No machines',
              'No machine data is available.',
            )
          else
            ...machines.map(_machineTile),
        ],
      ),
    );
  }

  Widget _machineTile(
    Map<String, dynamic> machine,
  ) {
    final health =
        _number(machine['health_score']);

    final color = health >= 70
        ? Colors.greenAccent
        : health >= 40
            ? Colors.amberAccent
            : Colors.redAccent;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _showMachine(machine),

        leading: CircleAvatar(
          backgroundColor:
              color.withOpacity(.12),
          child: Icon(
            Icons.precision_manufacturing,
            color: color,
          ),
        ),

        title: Text(
          '${machine['name'] ?? 'Machine'}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        subtitle: Text(
          '${machine['machine_code'] ?? '—'} • '
          '${machine['location'] ?? '—'}',
          style: const TextStyle(
            color: Colors.white54,
          ),
        ),

        trailing: Text(
          '${health.toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _showMachine(
    Map<String, dynamic> machine,
  ) {
    final health =
        _number(machine['health_score']);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          const Color(0xFF0B1728),
      showDragHandle: true,
      builder: (_) {
        return Padding(
          padding:
              const EdgeInsets.fromLTRB(
            20,
            5,
            20,
            30,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${machine['name'] ?? 'Machine'}',
                      style:
                          const TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                  ),
                  _statusChip(health),
                ],
              ),

              const SizedBox(height: 14),

              _detailRow(
                'Machine code',
                '${machine['machine_code'] ?? '—'}',
              ),

              _detailRow(
                'Location',
                '${machine['location'] ?? '—'}',
              ),

              _detailRow(
                'Department',
                '${machine['department'] ?? '—'}',
              ),

              _detailRow(
                'Operating hours',
                '${machine['operating_hours'] ?? '—'}',
              ),

              _detailRow(
                'Maintenance interval',
                '${machine['maintenance_interval_hours'] ?? '—'} h',
              ),

              const SizedBox(height: 8),

              const Text(
                'Machine configuration is read-only here. '
                'Changes belong in the main management application.',
                style: TextStyle(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _workOrdersPage() {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(
            'My Work Orders',
            'Acknowledge, start and resolve assigned jobs',
          ),

          const SizedBox(height: 16),

          if (orders.isEmpty)
            _emptyState(
              'No work orders',
              'Assigned jobs will appear here.',
            )
          else
            ...orders.map(_workOrderCard),
        ],
      ),
    );
  }

  Widget _workOrderCard(
    Map<String, dynamic> order,
  ) {
    final status =
        '${order['status'] ?? 'pending'}'
            .toLowerCase();

    final priority =
        '${order['priority'] ?? 'medium'}'
            .toLowerCase();

    final color =
        priority == 'critical' ||
                priority == 'high'
            ? Colors.redAccent
            : priority == 'medium'
                ? Colors.amberAccent
                : Colors.lightBlueAccent;

    return Card(
      margin:
          const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'WO-${order['id'] ?? '—'}',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                ),
                _chip(
                  priority.toUpperCase(),
                  color,
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              '${order['problem'] ?? 'Maintenance work'}',
              style:
                  const TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.w700,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Machine #${order['machine_id'] ?? '—'}',
              style:
                  const TextStyle(
                color: Colors.white54,
              ),
            ),

            if ('${order['recommended_actions'] ?? ''}'
                .trim()
                .isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(
                  top: 8,
                ),
                child: Text(
                  '${order['recommended_actions']}',
                  style:
                      const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            Row(
              children: [
                _chip(
                  status
                      .replaceAll('_', ' ')
                      .toUpperCase(),
                  status == 'completed'
                      ? Colors.greenAccent
                      : Colors.lightBlueAccent,
                ),

                const Spacer(),

                if (status == 'pending')
                  OutlinedButton.icon(
                    onPressed: () =>
                        updateWorkOrder(
                      order,
                      'in_progress',
                    ),
                    icon:
                        const Icon(Icons.check),
                    label: const Text(
                      'Acknowledge',
                    ),
                  ),

                if (status == 'in_progress')
                  FilledButton.icon(
                    onPressed: () =>
                        _resolveWorkOrder(
                      order,
                    ),
                    icon: const Icon(
                      Icons.done_all,
                    ),
                    label: const Text(
                      'Resolve',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveWorkOrder(
    Map<String, dynamic> order,
  ) async {
    final controller =
        TextEditingController();

    final notes =
        await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title:
            const Text(
          'Resolve work order',
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration:
              const InputDecoration(
            labelText:
                'Resolution notes',
            hintText:
                'Describe the completed work...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context),
            child: const Text(
              'Cancel',
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              controller.text.trim(),
            ),
            child: const Text(
              'Resolve',
            ),
          ),
        ],
      ),
    );

    controller.dispose();

    if (notes == null ||
        notes.isEmpty) {
      return;
    }

    await updateWorkOrder(
      order,
      'completed',
      notes: notes,
    );
  }

  Widget _alertsPage() {
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(
            'Alerts',
            'Machine and maintenance events',
          ),

          const SizedBox(height: 16),

          if (alerts.isEmpty)
            _emptyState(
              'No alerts',
              'There are no alerts currently.',
            )
          else
            ...alerts.map(
              (alert) => Card(
                margin:
                    const EdgeInsets.only(
                  bottom: 10,
                ),
                child: ListTile(
                  leading: Icon(
                    alert['resolved'] == true
                        ? Icons.check_circle
                        : Icons.warning_amber,
                    color:
                        alert['resolved'] == true
                            ? Colors.greenAccent
                            : Colors.amberAccent,
                  ),

                  title: Text(
                    '${alert['alert_type'] ?? 'Alert'}',
                  ),

                  subtitle: Text(
                    '${alert['message'] ?? 'No message'}',
                  ),

                  trailing: Text(
                    '${alert['severity'] ?? 'unknown'}'
                        .toUpperCase(),
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _morePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          'More',
          'Connection and client information',
        ),

        const SizedBox(height: 14),

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.notifications_active_outlined,
            ),
            title:
                const Text(
              'Notifications',
            ),
            subtitle:
                const Text(
              'New work orders and alerts can surface while this client is running. '
              'Push notifications will be added with authentication.',
            ),
          ),
        ),

        Card(
          child: ListTile(
            leading:
                const Icon(
              Icons.cloud_outlined,
            ),
            title:
                const Text(
              'Backend',
            ),
            subtitle:
                const Text(
              apiBaseUrl,
            ),
          ),
        ),

        Card(
          child: ListTile(
            leading:
                const Icon(
              Icons.info_outline,
            ),
            title:
                const Text(
              'About',
            ),
            subtitle:
                const Text(
              'Industrial Workforce Client • field maintenance edition',
            ),
          ),
        ),

        const SizedBox(height: 10),

        const Text(
          'Authentication is intentionally disabled in this initial version.',
          style:
              TextStyle(
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    String title,
    String subtitle,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              const TextStyle(
            fontSize: 27,
            fontWeight:
                FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style:
              const TextStyle(
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(
    String label,
    String value,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(
              icon,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style:
                  const TextStyle(
                fontSize: 21,
                fontWeight:
                    FontWeight.w900,
              ),
            ),
            Text(
              label,
              style:
                  const TextStyle(
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: ListTile(
        leading:
            Icon(
          icon,
          color: color,
        ),
        title:
            Text(label),
        trailing:
            Text(
          value,
          style:
              TextStyle(
            color: color,
            fontSize: 22,
            fontWeight:
                FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _orderPreview(
    Map<String, dynamic> order,
  ) {
    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: ListTile(
        title: Text(
          'WO-${order['id'] ?? '—'} • '
          '${order['problem'] ?? 'Maintenance'}',
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${order['status'] ?? 'pending'} • '
          '${order['priority'] ?? 'medium'}'
              .toUpperCase(),
        ),
      ),
    );
  }

  Widget _chip(
    String text,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration:
          BoxDecoration(
        color:
            color.withOpacity(.12),
        borderRadius:
            BorderRadius.circular(
          30,
        ),
      ),
      child: Text(
        text,
        style:
            TextStyle(
          color: color,
          fontSize: 10,
          fontWeight:
              FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statusChip(
    double health,
  ) {
    if (health >= 70) {
      return _chip(
        'HEALTHY',
        Colors.greenAccent,
      );
    }

    if (health >= 40) {
      return _chip(
        'ATTENTION',
        Colors.amberAccent,
      );
    }

    return _chip(
      'CRITICAL',
      Colors.redAccent,
    );
  }

  Widget _statusBanner(
    String text,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      padding:
          const EdgeInsets.all(12),
      decoration:
          BoxDecoration(
        color:
            Colors.amber.withOpacity(.10),
        borderRadius:
            BorderRadius.circular(13),
        border:
            Border.all(
          color:
              Colors.amber.withOpacity(.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.amberAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  const TextStyle(
                color: Colors.amberAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    String title,
    String subtitle,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 34,
              color: Colors.white38,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style:
                  const TextStyle(
                color: Colors.white54,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>>
      _demoMachines() {
    return [
      {
        'id': 1,
        'name':
            'Induction Motor M-04',
        'machine_code': 'M-004',
        'health_score': 86,
        'location': 'Bay 3',
        'department': 'Production',
        'operating_hours': 4120,
        'maintenance_interval_hours':
            500,
      },
      {
        'id': 2,
        'name':
            'Centrifugal Pump P-02',
        'machine_code': 'P-002',
        'health_score': 58,
        'location':
            'Utility Room',
        'department': 'Utilities',
        'operating_hours': 3120,
        'maintenance_interval_hours':
            500,
      },
      {
        'id': 3,
        'name':
            'Air Compressor AC-01',
        'machine_code': 'AC-001',
        'health_score': 94,
        'location':
            'Compressor House',
        'department': 'Utilities',
        'operating_hours': 2110,
        'maintenance_interval_hours':
            750,
      },
    ];
  }

  List<Map<String, dynamic>>
      _demoOrders() {
    return [
      {
        'id': 104,
        'machine_id': 1,
        'problem':
            'Excessive vibration',
        'priority': 'high',
        'status': 'pending',
      },
      {
        'id': 109,
        'machine_id': 2,
        'problem':
            'Temperature above normal',
        'priority': 'medium',
        'status':
            'in_progress',
      },
    ];
  }

  List<Map<String, dynamic>>
      _demoAlerts() {
    return [
      {
        'id': 1,
        'machine_id': 2,
        'alert_type':
            'temperature_anomaly',
        'severity': 'warning',
        'message':
            'Pump P-02 temperature is above its recent baseline.',
        'resolved': false,
      },
    ];
  }
}
