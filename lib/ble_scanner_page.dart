import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleScannerPage extends StatefulWidget {
  const BleScannerPage({super.key});

  @override
  State<BleScannerPage> createState() => _BleScannerPageState();
}

class _BleScannerPageState extends State<BleScannerPage> {
  StreamSubscription<List<ScanResult>>? _sub;
  final Map<String, ScanResult> _devices = {};
  bool _scanning = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    _devices.clear();
    setState(() => _scanning = true);

    _sub?.cancel();
    _sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        _devices[id] = r;
      }
      setState(() {});
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 9));
    await FlutterBluePlus.stopScan();

    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Buscar impresora BLE"),
        actions: [
          IconButton(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text(_scanning ? "Escaneando..." : "Pulsa refrescar para buscar")),
                if (_scanning) const SizedBox(width: 12),
                if (_scanning) const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final r = list[i];
                final name = r.device.advName.isNotEmpty
                    ? r.device.advName
                    : (r.advertisementData.advName.isNotEmpty
                        ? r.advertisementData.advName
                        : "(sin nombre)");

                return ListTile(
                  title: Text(name),
                  subtitle: Text("RSSI ${r.rssi} • ${r.device.remoteId.str}"),
                  trailing: ElevatedButton(
                    onPressed: () => Navigator.pop(context, r),
                    child: const Text("Elegir"),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
