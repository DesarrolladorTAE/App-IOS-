import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;

import 'printer_config.dart';
import 'printer_service.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  PrinterMode mode = PrinterMode.tcp;

  // TCP
  final hostCtrl = TextEditingController();
  final portCtrl = TextEditingController(text: "9100");

  // BLE
  ble.ScanResult? bleSelected;
  String? bleServiceUuid;
  String? bleCharUuid;
  bool bleWithoutResponse = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    hostCtrl.dispose();
    portCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await PrinterService.instance.loadConfig();
    if (cfg == null) return;

    setState(() {
      // si venía btClassic de configs viejas, lo forzamos a TCP
      mode = (cfg.mode == PrinterMode.btClassic) ? PrinterMode.tcp : cfg.mode;

      hostCtrl.text = cfg.host ?? "";
      portCtrl.text = (cfg.port ?? 9100).toString();

      bleServiceUuid = cfg.bleServiceUuid;
      bleCharUuid = cfg.bleCharUuid;
      bleWithoutResponse = cfg.bleWithoutResponse ?? true;
      // NOTA: no podemos reconstruir bleSelected solo con el id (no tenemos ScanResult)
      bleSelected = null;
    });
  }

  Future<void> _save() async {
    if (mode == PrinterMode.tcp) {
      final host = hostCtrl.text.trim();
      final port = int.tryParse(portCtrl.text.trim()) ?? 9100;

      if (host.isEmpty) throw Exception("Escribe la IP/Host de la impresora");

      await PrinterService.instance.saveConfig(
        PrinterConfig(mode: PrinterMode.tcp, host: host, port: port),
      );
      return;
    }

    // BLE
    if (bleSelected == null || bleServiceUuid == null || bleCharUuid == null) {
      throw Exception("Selecciona impresora BLE y detecta UUIDs de escritura");
    }

    await PrinterService.instance.saveConfig(
      PrinterConfig(
        mode: PrinterMode.ble,
        bleDeviceId: bleSelected!.device.remoteId.str,
        bleServiceUuid: bleServiceUuid,
        bleCharUuid: bleCharUuid,
        bleWithoutResponse: bleWithoutResponse,
      ),
    );
  }

  Future<void> _testPrint() async {
    await _save();
    await PrinterService.instance.printDemo();
  }

  Future<void> _pickBle() async {
    setState(() {
      bleSelected = null;
      bleServiceUuid = null;
      bleCharUuid = null;
      bleWithoutResponse = true;
    });

    final results = <ble.ScanResult>[];

    final sub = ble.FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        if (!results.any((x) => x.device.remoteId == r.device.remoteId)) {
          results.add(r);
        }
      }
      if (mounted) setState(() {});
    });

    await ble.FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    await Future.delayed(const Duration(seconds: 7));
    await ble.FlutterBluePlus.stopScan();
    await sub.cancel();

    if (!mounted) return;

    final chosen = await showModalBottomSheet<ble.ScanResult>(
      context: context,
      builder: (_) => ListView(
        children: results.map((r) {
          final name = r.device.advName.isNotEmpty
              ? r.device.advName
              : (r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : "(sin nombre)");
          return ListTile(
            title: Text(name),
            subtitle: Text("RSSI ${r.rssi} • ${r.device.remoteId.str}"),
            onTap: () => Navigator.pop(context, r),
          );
        }).toList(),
      ),
    );

    if (chosen == null) return;

    setState(() => bleSelected = chosen);

    try {
      await chosen.device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
    } catch (_) {}

    final services = await chosen.device.discoverServices();

    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          setState(() {
            bleServiceUuid = s.uuid.toString();
            bleCharUuid = c.uuid.toString();
            bleWithoutResponse = c.properties.writeWithoutResponse;
          });
          return;
        }
      }
    }

    throw Exception("Conectó, pero no encontré characteristic de escritura");
  }

  @override
  Widget build(BuildContext context) {
    final bleInfo = (bleSelected == null)
        ? "Sin impresora BLE"
        : "BLE: ${bleSelected!.device.advName.isNotEmpty ? bleSelected!.device.advName : bleSelected!.device.remoteId.str}";

    final uuidInfo = (bleServiceUuid == null || bleCharUuid == null)
        ? "UUIDs de escritura: (no detectados)"
        : "Service: $bleServiceUuid\nChar: $bleCharUuid\nWithoutResponse: $bleWithoutResponse";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Configurar impresora"),
        actions: [
          IconButton(
            tooltip: "Imprimir prueba",
            icon: const Icon(Icons.print),
            onPressed: () async {
              try {
                await _testPrint();
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
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text("Modo", style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<PrinterMode>(
            value: PrinterMode.tcp,
            groupValue: mode,
            title: const Text("Ethernet / Wi-Fi (TCP 9100)"),
            onChanged: (v) => setState(() => mode = v!),
          ),
          RadioListTile<PrinterMode>(
            value: PrinterMode.ble,
            groupValue: mode,
            title: const Text("Bluetooth BLE (iOS/Android)"),
            onChanged: (v) => setState(() => mode = v!),
          ),
          const Divider(),

          if (mode == PrinterMode.tcp) ...[
            TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(labelText: "IP / Host (ej. 192.168.0.55)"),
            ),
            TextField(
              controller: portCtrl,
              decoration: const InputDecoration(labelText: "Puerto", hintText: "9100"),
              keyboardType: TextInputType.number,
            ),
          ],

          if (mode == PrinterMode.ble) ...[
            ListTile(
              title: Text(bleInfo),
              subtitle: Text(uuidInfo),
              trailing: ElevatedButton(
                onPressed: _pickBle,
                child: const Text("Buscar"),
              ),
            ),
          ],

          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              try {
                await _save();
                if (!mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("❌ $e")),
                );
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }
}
