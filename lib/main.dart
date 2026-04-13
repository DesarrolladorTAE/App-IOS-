import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'printer/app_config.dart';
import 'printer/printer_service.dart';
import 'printer/printer_settings_page.dart';

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
  String? currentUrl;
  InAppWebViewController? webViewController;

  @override
  void initState() {
    super.initState();
    _loadInitialUrl();
  }

  Future<void> _loadInitialUrl() async {
    final cfg = await AppConfig.load();
    final url = AppConfig.urlForMode(cfg.startAccessMode);

    if (!mounted) return;
    setState(() {
      currentUrl = url;
      error = null;
      progress = 0;
    });
  }

  Future<void> _reloadFromConfig() async {
    final cfg = await AppConfig.load();
    final url = AppConfig.urlForMode(cfg.startAccessMode);

    if (!mounted) return;

    setState(() {
      currentUrl = url;
      error = null;
      progress = 0;
    });

    if (webViewController != null) {
      await webViewController!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUrl == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("MI TIENDA EN LINEAMX"),
        actions: [
          IconButton(
            tooltip: "Configurar impresora y app",
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final shouldReloadWebView = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const PrinterSettingsPage()),
              );

              if (shouldReloadWebView == true) {
                await _reloadFromConfig();
              }

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Configuración guardada")),
              );
            },
          ),
          IconButton(
            tooltip: "Recargar vista",
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _reloadFromConfig();
            },
          ),
          IconButton(
            tooltip: "Imprimir prueba",
            icon: const Icon(Icons.print),
            onPressed: () async {
              try {
                await PrinterService.instance.printDemo();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Impresión enviada")),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("❌ $e")));
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(currentUrl!)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              useHybridComposition: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;

              controller.addJavaScriptHandler(
                handlerName: 'printTicket',
                callback: (args) async {
                  try {
                    if (args.isEmpty) {
                      throw Exception("No se recibió request de impresión");
                    }

                    final raw = args.first;
                    final request = Map<String, dynamic>.from(raw as Map);

                    final payloadRaw = request["payload"];
                    if (payloadRaw == null || payloadRaw is! Map) {
                      throw Exception("No se recibió payload válido");
                    }

                    final payload = Map<String, dynamic>.from(payloadRaw);

                    final host = (request["host"] ?? "").toString().trim();

                    int? port;
                    final portRaw = request["port"];
                    if (portRaw is num) {
                      port = portRaw.toInt();
                    } else if (portRaw != null) {
                      port = int.tryParse(portRaw.toString());
                    }

                    await PrinterService.instance.printJob(
                      payload,
                      host: host.isEmpty ? null : host,
                      port: port,
                    );

                    return {"ok": true, "message": "Impresión enviada"};
                  } catch (e, st) {
                    debugPrint("bridge printTicket -> error: $e");
                    debugPrint("$st");
                    return {"ok": false, "message": e.toString()};
                  }
                },
              );
            },
            onProgressChanged: (controller, p) {
              if (!mounted) return;
              setState(() => progress = p / 100.0);
            },
            onReceivedError: (controller, request, errorObj) {
              if (!mounted) return;
              setState(() => error = errorObj.description);
            },
            onReceivedHttpError: (controller, request, responseError) {
              if (!mounted) return;
              setState(() {
                error = "HTTP ${responseError.statusCode}";
              });
            },
          ),
          if (progress < 1 && error == null)
            LinearProgressIndicator(value: progress),
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
