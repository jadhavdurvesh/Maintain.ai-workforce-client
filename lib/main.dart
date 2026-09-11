import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = 'https://maintain-ai-3.vercel.app';

void main() => runApp(const WorkforceApp());

class Api {
  Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$apiBaseUrl$path')).timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body);
  }
  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final r = await http.patch(Uri.parse('$apiBaseUrl$path'), headers: {'Content-Type':'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception('HTTP ${r.statusCode}: ${r.body}');
    return jsonDecode(r.body);
  }
}

class WorkforceApp extends StatelessWidget {
  const WorkforceApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Industrial Workforce', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3:true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D8BFF), brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xFF08111F), cardTheme: const CardThemeData(color: Color(0xFF111D2E))),
    home: const Home(),
  );
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> {
  final api=Api(); int tab=0; bool busy=true; String? message; Timer? timer;
  List<Map<String,dynamic>> machines=[]; List<Map<String,dynamic>> orders=[]; List<Map<String,dynamic>> alerts=[];
  @override void initState(){super.initState(); refresh(); timer=Timer.periodic(const Duration(seconds:10),(_)=>refresh(silent:true));}
  @override void dispose(){timer?.cancel();super.dispose();}
  Future<void> refresh({bool silent=false}) async {
    if(!silent&&mounted)setState(()=>busy=true);
    try {
      final x=await Future.wait([api.get('/api/machines'),api.get('/api/work-orders'),api.get('/api/alerts')]);
      if(!mounted)return; setState((){machines=_maps(x[0]);orders=_maps(x[1]);alerts=_maps(x[2]);busy=false;message=null;});
    } catch(e){ if(!mounted)return; setState(()=>busy=false); if(machines.isEmpty) setState(()=>message='Backend unavailable — demo data is shown.'); }
  }
  List<Map<String,dynamic>> _maps(dynamic v)=>v is List?v.map((e)=>Map<String,dynamic>.from(e as Map)).toList():[];
  double numv(dynamic v)=>double.tryParse('$v')??0;
  Future<void> orderStatus(Map<String,dynamic> o,String status,{String? notes}) async {
    try { await api.patch('/api/work-orders/${o['id']}',{'status':status,if(notes!=null)'resolution_notes':notes}); _snack('Work order updated'); await refresh(silent:true); }
    catch(e){_snack('Update failed: $e',error:true);}
  }
  void _snack(String s,{bool error=false})=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating,backgroundColor:error?Colors.red.shade900:Colors.green.shade900));
  @override Widget build(BuildContext context){
    final pages=[dashboard(),machinesPage(),ordersPage(),alertsPage(),morePage()];
    return Scaffold(appBar:AppBar(title:const Text('Industrial Workforce',style:TextStyle(fontWeight:FontWeight.w800)),actions:[if(busy)const Padding(padding:EdgeInsets.all(15),child:SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))),IconButton(onPressed:()=>refresh(),icon:const Icon(Icons.refresh))]),body:pages[tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[
      NavigationDestination(icon:Icon(Icons.dashboard_outlined),selectedIcon:Icon(Icons.dashboard),label:'Home'),NavigationDestination(icon:Icon(Icons.precision_manufacturing_outlined),selectedIcon:Icon(Icons.precision_manufacturing),label:'Machines'),NavigationDestination(icon:Icon(Icons.assignment_outlined),selectedIcon:Icon(Icons.assignment),label:'Work Orders'),NavigationDestination(icon:Icon(Icons.notifications_none),selectedIcon:Icon(Icons.notifications),label:'Alerts'),NavigationDestination(icon:Icon(Icons.more_horiz),selectedIcon:Icon(Icons.more_horiz),label:'More')]),);
  }
  Widget dashboard(){final avg=machines.isEmpty?0:machines.map((m)=>numv(m['health_score'])).reduce((a,b)=>a+b)/machines.length;final open=orders.where((o)=>'${o['status']}'.toLowerCase()!='completed').length;final active=alerts.where((a)=>a['resolved']!=true).length;return ListView(padding:const EdgeInsets.all(16),children:[if(message!=null)_banner(message!),Card(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Worker Dashboard',style:TextStyle(color:Colors.white60)),Text(avg==0?'—':'${avg.toStringAsFixed(0)}%',style:const TextStyle(fontSize:42,fontWeight:FontWeight.w900)),const Text('Average machine health',style:TextStyle(color:Colors.white54))])),const CircleAvatar(radius:34,child:Icon(Icons.engineering,size:34))]))),const SizedBox(height:14),Row(children:[Expanded(child:metric('Machines','${machines.length}',Icons.precision_manufacturing)),const SizedBox(width:10),Expanded(child:metric('Open Jobs','$open',Icons.assignment)),const SizedBox(width:10),Expanded(child:metric('Alerts','$active',Icons.warning_amber))]),const SizedBox(height:22),const Text('My Machines',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),const SizedBox(height:10),...machines.take(5).map(machineTile),const SizedBox(height:18),Row(children:[const Expanded(child:Text('Assigned Work',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),TextButton(onPressed:()=>setState(()=>tab=2),child:const Text('View all'))]),...orders.take(3).map(orderTile)]);}
  Widget machinesPage()=>RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(16),children:[const Text('My Machines',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),const SizedBox(height:6),const Text('Machine status and health for the workforce view.',style:TextStyle(color:Colors.white54)),const SizedBox(height:16),...machines.map(machineTile),if(machines.isEmpty)empty('No machines','No machine data is available.') ]));
  Widget machineTile(Map<String,dynamic> m){final h=numv(m['health_score']);final c=h>=70?Colors.greenAccent:h>=40?Colors.amberAccent:Colors.redAccent;return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(onTap:()=>showMachine(m),leading:CircleAvatar(backgroundColor:c.withOpacity(.12),child:Icon(Icons.precision_manufacturing,color:c)),title:Text('${m['name']??'Machine'}',style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${m['machine_code']??'—'} • ${m['location']??'—'}',style:const TextStyle(color:Colors.white54)),trailing:Text('${h.toStringAsFixed(0)}%',style:TextStyle(color:c,fontWeight:FontWeight.w900))));}
  void showMachine(Map<String,dynamic> m)=>showModalBottomSheet(context:context,backgroundColor:const Color(0xFF0B1728),showDragHandle:true,builder:(_)=>Padding(padding:const EdgeInsets.fromLTRB(20,5,20,30),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${m['name']}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:14),detail('Machine code','${m['machine_code']??'—'}'),detail('Location','${m['location']??'—'}'),detail('Department','${m['department']??'—'}'),detail('Operating hours','${m['operating_hours']??'—'}'),detail('Maintenance interval','${m['maintenance_interval_hours']??'—'} h'),const SizedBox(height:8),const Text('Machine configuration is read-only here. Changes belong in the main management application.',style:TextStyle(color:Colors.white54))])));
  Widget ordersPage()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('My Work Orders',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),const SizedBox(height:6),const Text('Acknowledge, start and resolve jobs assigned to you.',style:TextStyle(color:Colors.white54)),const SizedBox(height:16),...orders.map(workOrder),if(orders.isEmpty)empty('No work orders','Assigned jobs will appear here.')]);
  Widget workOrder(Map<String,dynamic> o){final status='${o['status']??'pending'}'.toLowerCase();final p='${o['priority']??'medium'}'.toLowerCase();final c=p=='critical'||p=='high'?Colors.redAccent:p=='medium'?Colors.amberAccent:Colors.lightBlueAccent;return Card(margin:const EdgeInsets.only(bottom:12),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text('WO-${o['id']??'—'}',style:const TextStyle(fontWeight:FontWeight.w900))),chip(p.toUpperCase(),c)]),const SizedBox(height:8),Text('${o['problem']??'Maintenance work'}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),Text('Machine #${o['machine_id']??'—'}',style:const TextStyle(color:Colors.white54)),if('${o['recommended_actions']??''}'.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('${o['recommended_actions']}',style:const TextStyle(color:Colors.white70))),const SizedBox(height:12),Row(children:[chip(status.replaceAll('_',' ').toUpperCase(),Colors.lightBlueAccent),const Spacer(),if(status=='pending')OutlinedButton.icon(onPressed:()=>orderStatus(o,'in_progress'),icon:const Icon(Icons.check),label:const Text('Acknowledge')),if(status=='in_progress')FilledButton.icon(onPressed:()=>resolve(o),icon:const Icon(Icons.done_all),label:const Text('Resolve'))])])));}
  Future<void> resolve(Map<String,dynamic> o)async{final c=TextEditingController();final notes=await showDialog<String>(context:context,builder:(_)=>AlertDialog(title:const Text('Resolve work order'),content:TextField(controller:c,maxLines:4,decoration:const InputDecoration(labelText:'Resolution notes',hintText:'Describe completed work')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,c.text.trim()),child:const Text('Resolve'))]));if(notes!=null&&notes.isNotEmpty)await orderStatus(o,'completed',notes:notes);}
  Widget alertsPage()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('Alerts',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),const SizedBox(height:6),const Text('Machine and maintenance events.',style:TextStyle(color:Colors.white54)),const SizedBox(height:16),...alerts.map((a)=>Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:Icon(a['resolved']==true?Icons.check_circle:Icons.warning_amber,color:a['resolved']==true?Colors.greenAccent:Colors.amberAccent),title:Text('${a['alert_type']??'Alert'}'),subtitle:Text('${a['message']??'No message'}'),trailing:Text('${a['severity']??'unknown'}'.toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w800)))),if(alerts.isEmpty)empty('No alerts','There are no alerts currently.')]);
  Widget morePage()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('More',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),const SizedBox(height:14),Card(child:ListTile(leading:const Icon(Icons.notifications_active_outlined),title:const Text('Notifications'),subtitle:const Text('Live notifications will be connected with the authenticated workforce service later.'))),Card(child:ListTile(leading:const Icon(Icons.cloud_outlined),title:const Text('Backend'),subtitle:const Text(apiBaseUrl))),Card(child:ListTile(leading:const Icon(Icons.info_outline),title:const Text('About'),subtitle:const Text('Industrial Workforce Client • MAINTAIN AI workforce edition'))),const SizedBox(height:10),const Text('Authentication is intentionally disabled in this initial version.',style:TextStyle(color:Colors.white54))]);
  Widget metric(String l,String v,IconData i)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Icon(i,color:Colors.lightBlueAccent),const SizedBox(height:5),Text(v,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),Text(l,style:const TextStyle(fontSize:11,color:Colors.white54))])));
  Widget chip(String s,Color c)=>Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:c.withOpacity(.12),borderRadius:BorderRadius.circular(30)),child:Text(s,style:TextStyle(color:c,fontSize:10,fontWeight:FontWeight.w900)));
  Widget orderTile(Map<String,dynamic> o)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(title:Text('WO-${o['id']??'—'} • ${o['problem']??'Maintenance'}',maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('${o['status']??'pending'} • ${o['priority']??'medium'}'.toUpperCase())));
  Widget banner(String s)=>Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.amber.withOpacity(.10),borderRadius:BorderRadius.circular(13)),child:Text(s,style:const TextStyle(color:Colors.amberAccent)));
  Widget empty(String a,String b)=>Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[const Icon(Icons.inbox_outlined,size:34,color:Colors.white38),const SizedBox(height:8),Text(a,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(b,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white54))]));
  Widget detail(String a,String b)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(children:[SizedBox(width:150,child:Text(a,style:const TextStyle(color:Colors.white54))),Expanded(child:Text(b))]));
}
