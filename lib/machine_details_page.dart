import 'package:flutter/material.dart';

class MachineDetailsPage extends StatefulWidget {
  final dynamic api;
  final Map<String, dynamic> machine;

  const MachineDetailsPage({
    super.key,
    required this.api,
    required this.machine,
  });

  @override
  State<MachineDetailsPage> createState() => _MachineDetailsPageState();
}

class _MachineDetailsPageState extends State<MachineDetailsPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> components = [];
  List<Map<String, dynamic>> readings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final id = widget.machine['id'];
      final results = await Future.wait<dynamic>([
        widget.api.get('/api/machines/' + id.toString() + '/components'),
        widget.api.get('/api/machines/' + id.toString() + '/readings'),
      ]);

      if (!mounted) return;
      setState(() {
        components = _maps(results[0]);
        readings = _maps(results[1]);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  double _number(dynamic value) => double.tryParse(value.toString()) ?? 0;

  String _pretty(String value) {
    return value.replaceAll('_', ' ').split(' ').map((part) {
      if (part.isEmpty) return part;
      return part[0].toUpperCase() + part.substring(1);
    }).join(' ');
  }

  IconData _sensorIcon(String type) {
    switch (type.toLowerCase()) {
      case 'temperature': return Icons.thermostat_outlined;
      case 'humidity': return Icons.water_drop_outlined;
      case 'vibration': return Icons.vibration;
      case 'current': return Icons.electric_bolt_outlined;
      case 'load': return Icons.speed_outlined;
      default: return Icons.sensors_outlined;
    }
  }

  Color _healthColor(double health) {
    if (health >= 70) return Colors.greenAccent;
    if (health >= 40) return Colors.amberAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final health = _number(widget.machine['health_score']);
    final healthColor = _healthColor(health);
    final types = <String>{
      ...readings.map((r) => (r['reading_type'] ?? '').toString().toLowerCase()),
    }.where((v) => v.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.machine['name']?.toString() ?? 'Machine',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            _header(health, healthColor),
            const SizedBox(height: 20),
            const Text('Sensor Readings', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (readings.isEmpty)
              _empty('No sensor readings', 'No readings have been recorded for this machine yet.'),
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: types.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.3,
                ),
                itemBuilder: (context, index) {
                  final type = types[index];
                  final reading = readings.firstWhere(
                    (item) => (item['reading_type'] ?? '').toString().toLowerCase() == type,
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(_sensorIcon(type), color: Colors.lightBlueAccent),
                          const Spacer(),
                          Text(_pretty(type), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            (reading['value'] ?? '—').toString() + (reading['unit'] ?? '').toString(),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 22),
            const Text('Components', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (loading)
              const SizedBox()
            else if (components.isEmpty)
              _empty('No components', 'No components have been registered for this machine.'),
            else
              ...components.map(
                (component) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.settings_outlined)),
                    title: Text(
                      (component['name'] ?? 'Component').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      (component['description'] ?? 'No description').toString(),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ),
            if (!loading && readings.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text('Recent Readings', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...readings.take(15).map(
                (reading) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.sensors_outlined, color: Colors.lightBlueAccent),
                    title: Text(_pretty((reading['reading_type'] ?? 'Reading').toString())),
                    subtitle: Text(
                      (reading['recorded_at'] ?? 'Unknown time').toString(),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: Text(
                      (reading['value'] ?? '—').toString() + (reading['unit'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(double health, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: color.withOpacity(.12),
                  child: Icon(Icons.precision_manufacturing, color: color, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.machine['name']?.toString() ?? 'Machine',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        widget.machine['machine_code']?.toString() ?? '—',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Text(
                  health.toStringAsFixed(0) + '%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detail('Location', widget.machine['location']?.toString() ?? '—'),
            _detail('Category', widget.machine['category']?.toString() ?? '—'),
            _detail('Status', widget.machine['status']?.toString() ?? '—'),
            _detail('Operating hours', widget.machine['operating_hours']?.toString() ?? '0'),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.white54))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _empty(String title, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, size: 34, color: Colors.white38),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
