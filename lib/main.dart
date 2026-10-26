import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:local_auth/local_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// >>> CHANGE THIS to your PeopleSoft URL <<<
const String kPeopleSoftUrl = 'https://ndr-hrms-uatweb.bankofindia.bank.in:8865/psp/uatmob/?cmd=login';

/// Re-lock the app if it was in background longer than this.
const Duration kRelockAfter = Duration(seconds: 60);


final _auth = LocalAuthentication();

//void main() {
//  WidgetsFlutterBinding.ensureInitialized();
//  runApp(const PeopleSoftApp());
//}

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await
  ScreenProtector.preventScreenshotOn();
  await ScreenProtector.protectDataLeakageWithBlur();
  runApp(const PeopleSoftApp());
}

class PeopleSoftApp extends StatelessWidget {
  const PeopleSoftApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PeopleSoft',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const LockPage(),
      );
}


class LockPage extends StatefulWidget {
  const LockPage({super.key});
  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_checking) return;
    setState(() { _checking = true; _error = null; });
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        setState(() => _error = 'Set up a fingerprint, face or screen lock in device settings.');
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Authenticate to open PeopleSoft',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PeopleSoftPage()));
      } else if (!ok) {
        setState(() => _error = 'Authentication failed. Try again.');
      }
    } catch (e) {
      setState(() => _error = 'Authentication error: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fingerprint, size: 96),
              const SizedBox(height: 16),
              const Text('App locked', style: TextStyle(fontSize: 20)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                  onPressed: _checking ? null : _authenticate,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock')),
            ]),
          ),
        ),
      );
}

class PeopleSoftPage extends StatefulWidget {
  const PeopleSoftPage({super.key});
  @override
  State<PeopleSoftPage> createState() => _PeopleSoftPageState();
}

class _PeopleSoftPageState extends State<PeopleSoftPage> with WidgetsBindingObserver {
  late final WebViewController _web;
  int _progress = 0;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onProgress: (p) => setState(() => _progress = p)))
      ..loadRequest(Uri.parse(kPeopleSoftUrl));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      if (DateTime.now().difference(_pausedAt!) > kRelockAfter && mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LockPage()));
      }
      _pausedAt = null;
    }
  }


  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _web.canGoBack()) await _web.goBack();
        },
        child: Scaffold(
          body: SafeArea(
         child: Column(
            children: [
              if (_progress < 100)
            LinearProgressIndicator(value: _progress / 100, minHeight: 2),
           Expanded(child: WebViewWidget(controller: _web)),
         ],
         ),
        ),
        ),
      );
}
