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
  void initState() {
    super.initState();
    Future.microtask(_scan);
  }

  @override
  void dispose() {
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  String _deviceName(ScanResult r) {
    if (r.device.advName.isNotEmpty) {
      return r.device.advName;
    }
    if (r.advertisementData.advName.isNotEmpty) {
      return r.advertisementData.advName;
    }
    return "(sin nombre)";
  }

  Future<void> _scan() async {
    if (_scanning) return;

    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Bluetooth apagado o no disponible"),
          ),
        );
        return;
      }

      _devices.clear();

      if (mounted) {
        setState(() => _scanning = true);
      }

      await FlutterBluePlus.stopScan();
      await _sub?.cancel();

      _sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final id = r.device.remoteId.str;
          _devices[id] = r;
        }

        if (mounted) {
          setState(() {});
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );

      await Future.delayed(const Duration(seconds: 9));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al escanear BLE: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
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
            tooltip: "Buscar de nuevo",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _scanning
                        ? "Escaneando impresoras..."
                        : "Selecciona una impresora BLE",
                  ),
                ),
                if (_scanning) const SizedBox(width: 12),
                if (_scanning)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty && !_scanning
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "No se encontraron dispositivos.\nPulsa refrescar para intentar de nuevo.",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final r = list[i];
                      final name = _deviceName(r);

                      return ListTile(
                        title: Text(name),
                        subtitle: Text(
                          "RSSI ${r.rssi} • ${r.device.remoteId.str}",
                        ),
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