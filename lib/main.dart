import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'printer/app_config.dart';
import 'printer/printer_settings_page.dart';
import 'printer/printer_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebTest(),
    );
  }
}

class WebTest extends StatefulWidget {
  const WebTest({super.key});

  @override
  State<WebTest> createState() => _WebTestState();
}

class _WebTestState extends State<WebTest> {
  double progress = 0;
  String? error;

  Timer? _pollTimer;
  bool _printing = false; // evita doble ejecución
  AppConfig? _appCfg;

  @override
  void initState() {
    super.initState();
    _loadAndStart();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAndStart() async {
    final cfg = await AppConfig.load();
    _appCfg = cfg;

    _startPolling(); // arranca si autoPrintEnabled
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _startPolling() async {
    _stopPolling();

    final cfg = _appCfg ?? await AppConfig.load();
    _appCfg = cfg;

    if (!cfg.autoPrintEnabled) return;

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_printing) return;

      try {
        _printing = true;

        // endpoints todavía no existen, pero la app queda lista
        final url = "${cfg.baseUrl}/print-jobs/next?device_id=${Uri.encodeComponent(cfg.deviceId)}";
        final res = await http.get(Uri.parse(url), headers: {
          "Accept": "application/json",
        });

        // ✅ si Laravel decide responder 204 cuando no hay jobs
        if (res.statusCode == 204) return;

        if (res.statusCode != 200) {
          // no rompemos, solo ignoramos
          return;
        }

        final data = jsonDecode(res.body);
        if (data == null) return;

        final jobIdRaw = data["id"];
        final payloadRaw = data["payload"];
        if (jobIdRaw == null || payloadRaw == null) return;

        final jobId = (jobIdRaw as num).toInt();
        final payload = Map<String, dynamic>.from(payloadRaw as Map);

        // 1) imprime con tu config (TCP o BLE)
        await PrinterService.instance.printJob(payload);

        // 2) confirma done
        await http.post(
          Uri.parse("${cfg.baseUrl}/print-jobs/$jobId/done"),
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
          },
          body: jsonEncode({}),
        );
      } catch (_) {
        // aquí luego metemos /failed cuando exista endpoint
      } finally {
        _printing = false;
      }
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrinterSettingsPage()),
    );

    // Recargar config por si cambiaron baseUrl/autoprint/deviceId
    _appCfg = await AppConfig.load();

    // Reiniciar polling según la config
    _startPolling();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Configuración guardada")),
    );
  }

  Future<void> _testPrint() async {
    try {
      await PrinterService.instance.printDemo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Impresión enviada")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MI TIENDA EN LINEAMX"),
        actions: [
          IconButton(
            tooltip: "Configurar impresora / SaaS",
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: "Imprimir prueba",
            icon: const Icon(Icons.print),
            onPressed: _testPrint,
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://mitiendaenlineamx.com.mx/"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              useHybridComposition: true,
            ),
            onProgressChanged: (controller, p) {
              if (!mounted) return;
              setState(() => progress = p / 100.0);
            },
            onLoadError: (controller, url, code, message) {
              if (!mounted) return;
              setState(() => error = "($code) $message");
            },
            onLoadHttpError: (controller, url, statusCode, description) {
              if (!mounted) return;
              setState(() => error = "HTTP $statusCode: $description");
            },
          ),
          if (progress < 1 && error == null) LinearProgressIndicator(value: progress),
          if (error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error!, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
