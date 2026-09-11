import 'package:flutter/material.dart';

void main() => runApp(const WorkforceApp());

class WorkforceApp extends StatelessWidget {
  const WorkforceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Industrial Workforce Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const WorkforceHome(),
    );
  }
}

class WorkforceHome extends StatefulWidget {
  const WorkforceHome({super.key});
  @override State<WorkforceHome> createState() => _WorkforceHomeState();
}

class _WorkforceHomeState extends State<WorkforceHome> {
  int index = 0;
  final machines = const [
    ('Motor M-04', 'Healthy', '72%'),
    ('Pump P-02', 'Warning', '54%'),
    ('Compressor C-01', 'Healthy', '88%'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _machines(),
      _workOrders(),
      _more(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Industrial Workforce')),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.precision_manufacturing_outlined), selectedIcon: Icon(Icons.precision_manufacturing), label: 'Machines'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Work Orders'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.engineering)), title: const Text('Worker Demo Mode'), subtitle: const Text('Authentication will be connected later.'))),
    const SizedBox(height: 12),
    const Text('My Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Row(children: [Expanded(child: _metric('Machines', '3', Icons.precision_manufacturing)), const SizedBox(width: 10), Expanded(child: _metric('Open Jobs', '2', Icons.assignment)), const SizedBox(width: 10), Expanded(child: _metric('Alerts', '1', Icons.warning_amber))]),
    const SizedBox(height: 20),
    const Text('Assigned Machines', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ...machines.map((m) => Card(child: ListTile(title: Text(m.$1), subtitle: Text(m.$2), trailing: Text(m.$3, style: const TextStyle(fontWeight: FontWeight.bold))))),
  ]);

  Widget _machines() => ListView(padding: const EdgeInsets.all(16), children: [const Text('My Machines', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12), ...machines.map((m) => Card(child: ListTile(leading: const Icon(Icons.precision_manufacturing), title: Text(m.$1), subtitle: Text('Health: ${m.$2}'), trailing: Text(m.$3))))]);

  Widget _workOrders() => ListView(padding: const EdgeInsets.all(16), children: [const Text('My Work Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12), _order('WO-104', 'Motor M-04', 'Excessive vibration', 'High', Icons.priority_high), _order('WO-109', 'Pump P-02', 'Temperature above normal', 'Medium', Icons.build),]);

  Widget _order(String id, String machine, String issue, String priority, IconData icon) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(child: Icon(icon)), title: Text('$id · $machine'), subtitle: Text(issue), trailing: Chip(label: Text(priority))));

  Widget _more() => ListView(padding: const EdgeInsets.all(16), children: [const Text('More', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const ListTile(leading: Icon(Icons.notifications_outlined), title: Text('Notifications'), subtitle: Text('Work-order and machine alerts')), const ListTile(leading: Icon(Icons.info_outline), title: Text('About'), subtitle: Text('Industrial Workforce Client · 0.1.0')),]);

  Widget _metric(String label, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Icon(icon), const SizedBox(height: 6), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(fontSize: 12))])));
}
