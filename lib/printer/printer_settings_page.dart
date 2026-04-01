import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;

import '../ble_scanner_page.dart';
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
  String? bleDeviceIdSaved;
  String? bleDeviceNameSaved;
  String? bleServiceUuid;
  String? bleCharUuid;
  bool bleWithoutResponse = true;
  bool _resolvingBle = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    hostCtrl.dispose();
    portCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await PrinterService.instance.loadConfig();

      if (!mounted || cfg == null) return;

      setState(() {
        mode = (cfg.mode == PrinterMode.btClassic)
            ? PrinterMode.tcp
            : cfg.mode;

        hostCtrl.text = cfg.host ?? "";
        portCtrl.text = (cfg.port ?? 9100).toString();

        bleDeviceIdSaved = cfg.bleDeviceId;
        bleDeviceNameSaved = cfg.bleDeviceName;
        bleServiceUuid = cfg.bleServiceUuid;
        bleCharUuid = cfg.bleCharUuid;
        bleWithoutResponse = cfg.bleWithoutResponse ?? true;

        bleSelected = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error cargando configuración: $e")),
      );
    }
  }

  Future<void> _save() async {
    if (mode == PrinterMode.tcp) {
      final host = hostCtrl.text.trim();
      final port = int.tryParse(portCtrl.text.trim()) ?? 9100;

      if (host.isEmpty) {
        throw Exception("Ingresa la IP/Host de la impresora");
      }

      await PrinterService.instance.saveConfig(
        PrinterConfig(
          mode: PrinterMode.tcp,
          host: host,
          port: port,
        ),
      );
      return;
    }

    final selectedDeviceId = bleSelected?.device.remoteId.str ?? bleDeviceIdSaved;
    final selectedDeviceName = bleSelected != null
        ? _deviceDisplayName(bleSelected!)
        : bleDeviceNameSaved;

    if (selectedDeviceId == null ||
        selectedDeviceId.isEmpty ||
        bleServiceUuid == null ||
        bleServiceUuid!.isEmpty ||
        bleCharUuid == null ||
        bleCharUuid!.isEmpty) {
      throw Exception("Selecciona impresora BLE y detecta UUIDs de escritura");
    }

    await PrinterService.instance.saveConfig(
      PrinterConfig(
        mode: PrinterMode.ble,
        bleDeviceId: selectedDeviceId,
        bleDeviceName: selectedDeviceName,
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

  String _deviceDisplayName(ble.ScanResult result) {
    if (result.device.advName.isNotEmpty) {
      return result.device.advName;
    }
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    return result.device.remoteId.str;
  }

  Future<void> _pickBle() async {
    if (_resolvingBle) return;

    setState(() {
      _resolvingBle = true;
      bleSelected = null;
      bleServiceUuid = null;
      bleCharUuid = null;
      bleWithoutResponse = true;
    });

    ble.ScanResult? chosen;

    try {
      chosen = await Navigator.push<ble.ScanResult>(
        context,
        MaterialPageRoute(builder: (_) => const BleScannerPage()),
      );

      if (!mounted) return;

      if (chosen == null) {
        setState(() => _resolvingBle = false);
        return;
      }

      setState(() {
        bleSelected = chosen;
        bleDeviceIdSaved = chosen!.device.remoteId.str;
        bleDeviceNameSaved = _deviceDisplayName(chosen);
      });

      try {
        await chosen.device.connect(
          timeout: const Duration(seconds: 10),
          autoConnect: false,
        );
      } catch (_) {}

      final services = await chosen.device.discoverServices();

      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            if (!mounted) return;

            setState(() {
              bleServiceUuid = s.uuid.toString();
              bleCharUuid = c.uuid.toString();
              bleWithoutResponse = c.properties.writeWithoutResponse;
              _resolvingBle = false;
            });
            return;
          }
        }
      }

      throw Exception("Conectó, pero no encontré characteristic de escritura");
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolvingBle = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error BLE: $e")),
      );
    } finally {
      if (chosen != null) {
        try {
          await chosen.device.disconnect();
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() => _resolvingBle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentBleName = bleSelected != null
        ? _deviceDisplayName(bleSelected!)
        : (bleDeviceNameSaved?.isNotEmpty == true
              ? bleDeviceNameSaved!
              : (bleDeviceIdSaved?.isNotEmpty == true
                    ? bleDeviceIdSaved!
                    : "Sin impresora BLE"));

    final bleInfo = "BLE: $currentBleName";

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
          const Text(
            "Modo de impresora",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          RadioListTile<PrinterMode>(
            value: PrinterMode.tcp,
            groupValue: mode,
            title: const Text("Ethernet / Wi-Fi (TCP 9100)"),
            onChanged: (v) {
              if (v == null) return;
              setState(() => mode = v);
            },
          ),
          RadioListTile<PrinterMode>(
            value: PrinterMode.ble,
            groupValue: mode,
            title: const Text("Bluetooth BLE (iOS/Android)"),
            onChanged: (v) {
              if (v == null) return;
              setState(() => mode = v);
            },
          ),
          const Divider(),

          if (mode == PrinterMode.tcp) ...[
            TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(
                labelText: "IP / Host",
                hintText: "192.168.1.118",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portCtrl,
              decoration: const InputDecoration(
                labelText: "Puerto",
                hintText: "9100",
              ),
              keyboardType: TextInputType.number,
            ),
          ],

          if (mode == PrinterMode.ble) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(bleInfo),
              subtitle: Text(uuidInfo),
              trailing: ElevatedButton(
                onPressed: _resolvingBle ? null : _pickBle,
                child: Text(_resolvingBle ? "Buscando..." : "Buscar"),
              ),
            ),
          ],

          const SizedBox(height: 20),
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