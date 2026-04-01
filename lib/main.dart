import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MI TIENDA EN LINEAMX"),
        actions: [
          IconButton(
            tooltip: "Configurar impresora",
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PrinterSettingsPage(),
                ),
              );

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Configuración guardada")),
              );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("❌ $e")),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://mitiendaenlineamx.com.mx/login-register"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              useHybridComposition: true,
            ),
            onWebViewCreated: (controller) {
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

                    debugPrint("bridge printTicket -> request keys: ${request.keys.toList()}");
                    debugPrint("bridge printTicket -> host: $host");
                    debugPrint("bridge printTicket -> port: $port");
                    debugPrint("bridge printTicket -> payload keys: ${payload.keys.toList()}");
                    debugPrint("bridge printTicket -> payload: $payload");

                    await PrinterService.instance.printJob(
                      payload,
                      host: host.isEmpty ? null : host,
                      port: port,
                    );

                    return {
                      "ok": true,
                      "message": "Impresión enviada",
                    };
                  } catch (e, st) {
                    debugPrint("bridge printTicket -> error: $e");
                    debugPrint("$st");
                    return {
                      "ok": false,
                      "message": e.toString(),
                    };
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
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}