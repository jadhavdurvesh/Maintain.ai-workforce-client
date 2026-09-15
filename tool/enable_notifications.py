from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

if "import 'notification_service.dart';" not in text:
    text = text.replace(
        "import 'package:shared_preferences/shared_preferences.dart';\n",
        "import 'package:shared_preferences/shared_preferences.dart';\nimport 'notification_service.dart';\n",
        1,
    )

text = text.replace(
    "void main() => runApp(const WorkforceApp());",
    """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const WorkforceApp());
}""",
    1,
)

restore_marker = """        initialized = true;
      });
    } catch (_) {"""
if "await NotificationService.initialize();" not in text[text.find("Future<void> _restoreSession"):text.find("Future<void> login")]:
    replacement = """        initialized = true;
      });
      await NotificationService.initialize();
    } catch (_) {"""
    text = text.replace(restore_marker, replacement, 1)

login_marker = """    setState(() {
      authenticated = true;
      worker = user;
    });
  }"""
if "await NotificationService.initialize();" not in text[text.find("Future<void> login"):text.find("Future<void> logout")]:
    text = text.replace(
        login_marker,
        """    setState(() {
      authenticated = true;
      worker = user;
    });
    await NotificationService.initialize();
  }""",
        1,
    )

logout_marker = """  Future<void> logout() async {
    await api.clearToken();"""
text = text.replace(
    logout_marker,
    """  Future<void> logout() async {
    await NotificationService.unregister();
    await api.clearToken();""",
    1,
)

appbar_marker = """        actions: [
          if (loading) const Padding(padding: EdgeInsets.all(15), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(onPressed: refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
        ],"""
if "NotificationService.openCenter" not in text:
    text = text.replace(
        appbar_marker,
        """        actions: [
          if (loading) const Padding(padding: EdgeInsets.all(15), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(
            onPressed: () => NotificationService.openCenter(context),
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(onPressed: refresh, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
        ],""",
        1,
    )

path.write_text(text, encoding='utf-8')
print('Notification integration applied to lib/main.dart')
