import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'realtime_service.dart';
import 'notification_service.dart';
import 'machine_details_page.dart';

const String apiBaseUrl = String.fromEnvironment('MAINTAIN_API_URL', defaultValue: 'https://maintain-ai-3.vercel.app');
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const String supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const WorkforceApp());
}

class ApiClient {
  String? token;

  Future<void> restoreToken() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('worker_access_token');
  }

  Future<Map<String, dynamic>> supabaseLogin(String email, String password) async {
    final response = await http.post(Uri.parse('$supabaseUrl/auth/v1/token?grant_type=password'), headers: {'apikey': supabasePublishableKey, 'Content-Type': 'application/json'}, body: jsonEncode({'email': email, 'password': password})).timeout(const Duration(seconds: 12));
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) throw ApiException((data is Map ? (data['error_description'] ?? data['msg']) : null)?.toString() ?? 'Sign in failed', response.statusCode);
    final token = data['access_token']?.toString();
    if (token == null) throw ApiException('No access token returned.', response.statusCode);
    await saveToken(token);
    await post('/api/auth/supabase/sync', body: {});
    final me = await get('/api/auth/me');
    return Map<String, dynamic>.from(me);
  }

  dynamic _decode(http.Response response) { try { return jsonDecode(response.body); } catch (_) { return response.body; } }

  Future<void> saveToken(String value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('worker_access_token', value);
  }

  Future<void> clearToken() async {
    token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('worker_access_token');
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'X-Maintain-Application': 'workforce',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path) async {
    final response = await http
        .get(Uri.parse('$apiBaseUrl$path'), headers: headers)
        .timeout(const Duration(seconds: 12));
    return _handle(response);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final response = await http
        .post(Uri.parse('$apiBaseUrl$path'), headers: headers, body: jsonEncode(body ?? {}))
        .timeout(const Duration(seconds: 12));
    return _handle(response);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final response = await http
        .patch(Uri.parse('$apiBaseUrl$path'), headers: headers, body: jsonEncode(body ?? {}))
        .timeout(const Duration(seconds: 12));
    return _handle(response);
  }

  dynamic _handle(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data is Map ? data['detail'] : null;
      throw ApiException(detail?.toString() ?? 'HTTP ${response.statusCode}', response.statusCode);
    }
    return data;
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

class WorkforceApp extends StatefulWidget {
  const WorkforceApp({super.key});
  @override
  State<WorkforceApp> createState() => _WorkforceAppState();
}

class _WorkforceAppState extends State<WorkforceApp> {
  final ApiClient api = ApiClient();
  bool initialized = false;
  bool authenticated = false;
  Map<String, dynamic>? worker;
  late final WorkforceRealtime realtime = WorkforceRealtime(apiBaseUrl: apiBaseUrl, supabaseUrl: supabaseUrl, supabasePublishableKey: supabasePublishableKey);

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await api.restoreToken();
    if (api.token == null) {
      if (mounted) setState(() => initialized = true);
      return;
    }
    try {
      final response = await api.get('/api/auth/me');
      if (!mounted) return;
      setState(() {
        authenticated = true;
        worker = Map<String, dynamic>.from(response);
        initialized = true;
      });
      await NotificationService.initialize();
      await realtime.start();
    } catch (_) {
      await api.clearToken();
      if (!mounted) return;
      setState(() {
        authenticated = false;
        worker = null;
        initialized = true;
      });
    }
  }

  Future<void> login(String token, Map<String, dynamic> user) async {
    await api.saveToken(token);
    if (!mounted) return;
    setState(() {
      authenticated = true;
      worker = user;
    });
    await NotificationService.initialize();
    await realtime.start();
  }

  Future<void> logout() async {
    await realtime.stop();
    await NotificationService.unregister();
    await api.clearToken();
    if (!mounted) return;
    setState(() {
      authenticated = false;
      worker = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'Industrial Workforce',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D8BFF), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF08111F),
        cardTheme: const CardTheme(color: Color(0xFF111D2E), elevation: 0, margin: EdgeInsets.zero),
      ),
      home: authenticated
          ? WorkforceHome(api: api, worker: worker!, onLogout: logout, realtime: realtime)
          : WorkerLoginPage(api: api, onLogin: login),
    );
  }
}

class WorkerLoginPage extends StatefulWidget {
  final ApiClient api;
  final Future<void> Function(String, Map<String, dynamic>) onLogin;
  const WorkerLoginPage({super.key, required this.api, required this.onLogin});
  @override
  State<WorkerLoginPage> createState() => _WorkerLoginPageState();
}

class _WorkerLoginPageState extends State<WorkerLoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final emailController = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final username = usernameController.text.trim();
    if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty && (email.isEmpty || password.isEmpty)) { setState(() => error = 'Enter your email and password.'); return; }
    if (supabaseUrl.isEmpty && username.isEmpty) { setState(() => error = 'Enter your username.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
        throw ApiException('Workforce authentication requires Supabase configuration.', 503);
      }
      final response = await widget.api.supabaseLogin(email, password);
      await widget.onLogin(response['access_token'].toString(), Map<String, dynamic>.from(response));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CircleAvatar(
                        radius: 34,
                        backgroundColor: Color(0x223D8BFF),
                        child: Icon(Icons.engineering, size: 36, color: Colors.lightBlueAccent),
                      ),
                      const SizedBox(height: 18),
                      const Text('Industrial Workforce', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      const Text('Worker Client', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 28),
                      if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) ...[
                        TextField(controller: emailController, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Work email', hintText: 'technician@company.com', prefixIcon: Icon(Icons.email_outlined))),
                        const SizedBox(height: 12),
                        TextField(controller: passwordController, obscureText: true, textInputAction: TextInputAction.done, onSubmitted: (_) => login(), decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
                      ] else TextField(
                        controller: usernameController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => login(),
                        decoration: const InputDecoration(labelText: 'Username', hintText: 'worker01', prefixIcon: Icon(Icons.person_outline)),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(error!, style: const TextStyle(color: Colors.redAccent)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: loading ? null : login,
                        child: loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Continue'),
                      ),
                      const SizedBox(height: 14),
                      const Text('Sign in with the account invited by your company administrator.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkforceHome extends StatefulWidget {
  final ApiClient api;
  final Map<String, dynamic> worker;
  final Future<void> Function() onLogout;
  final WorkforceRealtime realtime;
  const WorkforceHome({super.key, required this.api, required this.worker, required this.onLogout, required this.realtime});
  @override
  State<WorkforceHome> createState() => _WorkforceHomeState();
}

class _WorkforceHomeState extends State<WorkforceHome> {
  int tab = 0;
  bool loading = true;
  bool syncing = false;
  String? message;
  Timer? refreshTimer;
  List<Map<String, dynamic>> machines = [];
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> faults = [];

  @override
  void initState() {
    super.initState();
    refresh();
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => refresh(silent: true));
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  Future<void> refresh({bool silent = false}) async {
    if (syncing) return;
    syncing = true;
    if (!silent && mounted) setState(() { loading = true; message = null; });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.get('/api/machines'),
        widget.api.get('/api/work-orders'),
        widget.api.get('/api/faults'),
      ]);
      if (!mounted) return;
      setState(() {
        machines = _maps(results[0]);
        orders = _maps(results[1]);
        faults = _maps(results[2]);
        loading = false;
        message = null;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await widget.onLogout();
        return;
      }
      if (mounted) setState(() { loading = false; message = e.message; });
    } catch (e) {
      if (mounted) setState(() { loading = false; message = e.toString(); });
    } finally {
      syncing = false;
    }
  }

  void _showSnack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFF7C2231) : const Color(0xFF17402C),
    ));
  }

  Future<void> updateOrder(Map<String, dynamic> order, String status, {String? notes}) async {
    try {
      await widget.api.patch('/api/work-orders/${order['id']}', body: {
        'status': status,
        if (notes != null) 'resolution_notes': notes,
      });
      _showSnack('Work order updated.');
      await refresh(silent: true);
    } on ApiException catch (e) {
      if (e.statusCode == 401) { await widget.onLogout(); return; }
      _showSnack(e.message, error: true);
    } catch (e) {
      _showSnack('Could not update work order: $e', error: true);
    }
  }

  Future<void> reportFault() async {
    if (machines.isEmpty) {
      _showSnack('No assigned machines are available.', error: true);
      return;
    }
    int selectedMachine = machines.first['id'] as int;
    String severity = 'warning';
    final descriptionController = TextEditingController();
    final symptomsController = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1728),
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Report Fault / Anomaly', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('Report anything unusual you observe on an assigned machine.', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
        value: selectedMachine,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Machine',
          prefixIcon: Icon(Icons.precision_manufacturing),
        ),
        selectedItemBuilder: (context) => machines
            .map((machine) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${machine['name']} (${machine['machine_code']})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        items: machines
            .map((machine) => DropdownMenuItem<int>(
                  value: machine['id'] as int,
                  child: Text(
                    '${machine['name']} (${machine['machine_code']})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: (value) { if (value != null) setSheetState(() => selectedMachine = value); },
      ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'warning', child: Text('Warning')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'critical', child: Text('Critical')),
                  ],
                  onChanged: (value) { if (value != null) setSheetState(() => severity = value); },
                ),
                const SizedBox(height: 14),
                TextField(controller: descriptionController, maxLines: 3, decoration: const InputDecoration(labelText: 'What is wrong?', hintText: 'Example: Unusual vibration near the drive end.')),
                const SizedBox(height: 14),
                TextField(controller: symptomsController, maxLines: 3, decoration: const InputDecoration(labelText: 'Symptoms / observations', hintText: 'Example: Noise increased after startup.')),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final description = descriptionController.text.trim();
                      if (description.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Describe the fault first.')));
                        return;
                      }
                      try {
                        await widget.api.post('/api/faults', body: {
                          'machine_id': selectedMachine,
                          'description': description,
                          'symptoms': symptomsController.text.trim().isEmpty ? null : symptomsController.text.trim(),
                          'severity': severity,
                        });
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    },
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text('Submit Fault Report'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    descriptionController.dispose();
    symptomsController.dispose();
    if (result == true && mounted) {
      _showSnack('Fault reported successfully.');
      await refresh(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashboardPage(), _machinesPage(), _ordersPage(), _faultsPage(), _profilePage()];
    final name = widget.worker['full_name']?.toString();
    final username = widget.worker['username']?.toString() ?? 'worker';
    return Scaffold(
      appBar: AppBar(
        title: Text(name?.isNotEmpty == true ? name! : username, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (loading) const Padding(padding: EdgeInsets.all(15), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(
            onPressed: () => NotificationService.openCenter(context),
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(onPressed: refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: tab == 0 || tab == 1 ? FloatingActionButton.extended(onPressed: reportFault, icon: const Icon(Icons.report_problem_outlined), label: const Text('Report Fault')) : null,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFF111D2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(.07)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.28), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(children: [
            _navItem(0, Icons.dashboard_outlined, Icons.dashboard, 'Home'),
            _navItem(1, Icons.precision_manufacturing_outlined, Icons.precision_manufacturing, 'Machines'),
            _navItem(2, Icons.assignment_outlined, Icons.assignment, 'Work'),
            _navItem(3, Icons.report_problem_outlined, Icons.report_problem, 'Faults'),
            _navItem(4, Icons.person_outline, Icons.person, 'Profile'),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData selectedIcon, String label) {
    final selected = tab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? Colors.lightBlueAccent.withOpacity(.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: selected ? Colors.lightBlueAccent : Colors.white54),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.lightBlueAccent : Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardPage() {
    final average = machines.isEmpty ? 0.0 : machines.map((m) => _number(m['health_score'])).reduce((a, b) => a + b) / machines.length;
    final activeOrders = orders.where((o) => '${o['status']}'.toLowerCase() != 'completed').length;
    final openFaults = faults.where((f) => f['resolved_date'] == null).length;
    final critical = machines.where((m) => _number(m['health_score']) < 40).length;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (message != null) _statusBanner(message!),
          _hero(average),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _metricCard('Machines', '${machines.length}', Icons.precision_manufacturing)),
            const SizedBox(width: 10),
            Expanded(child: _metricCard('Open Jobs', '$activeOrders', Icons.assignment)),
            const SizedBox(width: 10),
            Expanded(child: _metricCard('Faults', '$openFaults', Icons.report_problem)),
          ]),
          const SizedBox(height: 10),
          _wideMetric('Critical machines', '$critical', Icons.warning_amber_rounded, critical > 0 ? Colors.redAccent : Colors.greenAccent),
          const SizedBox(height: 22),
          const Text('Assigned Machines', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (machines.isEmpty) _empty('No machines assigned', 'Your administrator has not assigned any machines yet.') else ...machines.take(5).map(_machineTile),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('My Work', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => setState(() => tab = 2), child: const Text('View all')),
          ]),
          if (orders.isEmpty) _empty('No work orders', 'Assigned maintenance jobs will appear here.') else ...orders.take(3).map(_orderPreview),
        ],
      ),
    );
  }

  Widget _hero(double average) {
    final color = average >= 70 ? Colors.greenAccent : average >= 40 ? Colors.amberAccent : Colors.redAccent;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Worker Dashboard', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 4),
            Text(average == 0 ? '—' : '${average.toStringAsFixed(0)}%', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: color)),
            const Text('Average machine health', style: TextStyle(color: Colors.white54)),
          ])),
          CircleAvatar(radius: 34, backgroundColor: color.withOpacity(.12), child: Icon(Icons.engineering, size: 34, color: color)),
        ]),
      ),
    );
  }

  Widget _machinesPage() => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('My Machines', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Only machines assigned to your account are shown.', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            if (machines.isEmpty) _empty('No machines assigned', 'Contact your administrator to receive machine assignments.') else ...machines.map(_machineTile),
          ],
        ),
      );

  Widget _machineTile(Map<String, dynamic> machine) {
    final health = _number(machine['health_score']);
    final color = health >= 70 ? Colors.greenAccent : health >= 40 ? Colors.amberAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MachineDetailsPage(api: widget.api, machine: machine))),
        leading: CircleAvatar(backgroundColor: color.withOpacity(.12), child: Icon(Icons.precision_manufacturing, color: color)),
        title: Text('${machine['name'] ?? 'Machine'}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${machine['machine_code'] ?? '—'} • ${machine['location'] ?? '—'}', style: const TextStyle(color: Colors.white54)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${health.toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ]),
      ),
    );
  }

  Widget _ordersPage() => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('My Work Orders', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Jobs assigned to your account.', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            if (orders.isEmpty) _empty('No work orders', 'You currently have no assigned work.') else ...orders.map(_workOrderCard),
          ],
        ),
      );

  Widget _workOrderCard(Map<String, dynamic> order) {
    final status = '${order['status'] ?? 'pending'}'.toLowerCase();
    final priority = '${order['priority'] ?? 'medium'}'.toLowerCase();
    final color = priority == 'critical' || priority == 'high' ? Colors.redAccent : priority == 'medium' ? Colors.amberAccent : Colors.lightBlueAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('WO-${order['id'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w900))), _chip(priority.toUpperCase(), color)]),
          const SizedBox(height: 8),
          Text('${order['problem'] ?? 'Maintenance work'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Machine #${order['machine_id'] ?? '—'}', style: const TextStyle(color: Colors.white54)),
          if ('${order['recommended_actions'] ?? ''}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${order['recommended_actions']}', style: const TextStyle(color: Colors.white70))),
          const SizedBox(height: 12),
          Row(children: [
            _chip(status.replaceAll('_', ' ').toUpperCase(), status == 'completed' ? Colors.greenAccent : Colors.lightBlueAccent),
            const Spacer(),
            if (status == 'pending') OutlinedButton.icon(onPressed: () => updateOrder(order, 'in_progress'), icon: const Icon(Icons.check), label: const Text('Acknowledge')),
            if (status == 'in_progress') FilledButton.icon(onPressed: () => _resolveOrder(order), icon: const Icon(Icons.done_all), label: const Text('Resolve')),
          ]),
        ]),
      ),
    );
  }

  Future<void> _resolveOrder(Map<String, dynamic> order) async {
    final controller = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resolve work order'),
        content: TextField(controller: controller, maxLines: 4, decoration: const InputDecoration(labelText: 'Resolution notes', hintText: 'Describe completed work...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Resolve')),
        ],
      ),
    );
    controller.dispose();
    if (notes == null || notes.isEmpty) return;
    await updateOrder(order, 'completed', notes: notes);
  }

  Widget _faultsPage() => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Reported Faults', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Faults and anomalies reported from your assigned machines.', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            if (faults.isEmpty) _empty('No reported faults', 'Faults you report will appear here.') else ...faults.map(_faultCard),
          ],
        ),
      );

  Widget _faultCard(Map<String, dynamic> fault) {
    final resolved = fault['resolved_date'] != null;
    final severity = '${fault['severity'] ?? 'warning'}'.toLowerCase();
    final color = severity == 'critical' ? Colors.redAccent : severity == 'high' ? Colors.orangeAccent : severity == 'warning' ? Colors.amberAccent : Colors.lightBlueAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('${fault['description'] ?? 'Fault'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), _chip(severity.toUpperCase(), color)]),
          const SizedBox(height: 8),
          if ('${fault['symptoms'] ?? ''}'.trim().isNotEmpty) Text('${fault['symptoms']}', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          Row(children: [_chip(resolved ? 'RESOLVED' : 'OPEN', resolved ? Colors.greenAccent : Colors.amberAccent), const Spacer(), Text('Fault #${fault['id'] ?? '—'}', style: const TextStyle(color: Colors.white38, fontSize: 11))]),
        ]),
      ),
    );
  }

  Widget _profilePage() {
    final username = widget.worker['username']?.toString() ?? 'worker';
    final name = widget.worker['full_name']?.toString();
    final organization = widget.worker['organization_name']?.toString() ?? 'Organization';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const CircleAvatar(radius: 30, child: Icon(Icons.person, size: 30)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name?.isNotEmpty == true ? name! : username, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('@$username', style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 4),
                Text(organization, style: const TextStyle(color: Colors.white54)),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Card(child: ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Role'), subtitle: Text(widget.worker['role']?.toString().toUpperCase() ?? 'TECHNICIAN'))),
        Card(child: ListTile(leading: const Icon(Icons.precision_manufacturing_outlined), title: const Text('Assigned Machines'), trailing: Text('${machines.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
        Card(child: ListTile(leading: const Icon(Icons.report_problem_outlined), title: const Text('Reported Faults'), trailing: Text('${faults.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(onPressed: widget.onLogout, icon: const Icon(Icons.logout), label: const Text('Sign Out')),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(icon, color: Colors.lightBlueAccent),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ),
      );

  Widget _wideMetric(String label, String value, IconData icon, Color color) => Card(
        child: ListTile(leading: Icon(icon, color: color), title: Text(label), trailing: Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800))),
      );

  Widget _orderPreview(Map<String, dynamic> order) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text('WO-${order['id'] ?? '—'} • ${order['problem'] ?? 'Maintenance'}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${order['status'] ?? 'pending'} • ${order['priority'] ?? 'medium'}'.toUpperCase()),
        ),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(30)),
        child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
      );

  Widget _statusBanner(String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.redAccent.withOpacity(.10), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.redAccent.withOpacity(.20))),
        child: Row(children: [const Icon(Icons.error_outline, color: Colors.redAccent), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(color: Colors.redAccent)))]),
      );

  Widget _empty(String title, String subtitle) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.inbox_outlined, size: 34, color: Colors.white38),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          ]),
        ),
      );
}
