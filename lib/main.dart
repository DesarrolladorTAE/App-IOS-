import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
                MaterialPageRoute(builder: (_) => const PrinterSettingsPage()),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Configuración guardada (si aplicaste Guardar)")),
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
              url: WebUri("https://mitiendaenlineamx.com.mx/"),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              useHybridComposition: true,
            ),
            onProgressChanged: (controller, p) {
              setState(() => progress = p / 100.0);
            },
            onLoadError: (controller, url, code, message) {
              setState(() => error = "($code) $message");
            },
            onLoadHttpError: (controller, url, statusCode, description) {
              setState(() => error = "HTTP $statusCode: $description");
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
