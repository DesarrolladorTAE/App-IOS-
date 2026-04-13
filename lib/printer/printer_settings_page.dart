import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;

import '../ble_scanner_page.dart';
import 'app_config.dart';
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

  // Config adicional
  PaperSizeMM selectedPaper = PaperSizeMM.mm80;
  bool autoCut = true;
  bool openDrawer = false;
  int drawerPin = 0;
  bool autoPrintEnabled = false;
  StartAccessMode startAccessMode = StartAccessMode.tienda;
  StartAccessMode _originalStartAccessMode = StartAccessMode.tienda;

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
      final printerCfg = await PrinterService.instance.loadConfig();
      final appCfg = await AppConfig.load();

      if (!mounted) return;

      setState(() {
        if (printerCfg != null) {
          mode = printerCfg.mode == PrinterMode.btClassic
              ? PrinterMode.tcp
              : printerCfg.mode;

          hostCtrl.text = printerCfg.host ?? "";
          portCtrl.text = (printerCfg.port ?? 9100).toString();

          bleDeviceIdSaved = printerCfg.bleDeviceId;
          bleDeviceNameSaved = printerCfg.bleDeviceName;
          bleServiceUuid = printerCfg.bleServiceUuid;
          bleCharUuid = printerCfg.bleCharUuid;
          bleWithoutResponse = printerCfg.bleWithoutResponse ?? true;

          selectedPaper = printerCfg.paperSize;
          autoCut = printerCfg.autoCut;
          openDrawer = printerCfg.openDrawer;
          drawerPin = printerCfg.drawerPin;

          bleSelected = null;
        }

        autoPrintEnabled = appCfg.autoPrintEnabled;
        startAccessMode = appCfg.startAccessMode;
        _originalStartAccessMode = appCfg.startAccessMode;
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
          paperSize: selectedPaper,
          autoCut: autoCut,
          openDrawer: openDrawer,
          drawerPin: drawerPin,
        ),
      );
    } else {
      final selectedDeviceId =
          bleSelected?.device.remoteId.str ?? bleDeviceIdSaved;
      final selectedDeviceName = bleSelected != null
          ? _deviceDisplayName(bleSelected!)
          : bleDeviceNameSaved;

      if (selectedDeviceId == null ||
          selectedDeviceId.isEmpty ||
          bleServiceUuid == null ||
          bleServiceUuid!.isEmpty ||
          bleCharUuid == null ||
          bleCharUuid!.isEmpty) {
        throw Exception(
          "Selecciona impresora BLE y detecta UUIDs de escritura",
        );
      }

      await PrinterService.instance.saveConfig(
        PrinterConfig(
          mode: PrinterMode.ble,
          bleDeviceId: selectedDeviceId,
          bleDeviceName: selectedDeviceName,
          bleServiceUuid: bleServiceUuid,
          bleCharUuid: bleCharUuid,
          bleWithoutResponse: bleWithoutResponse,
          paperSize: selectedPaper,
          autoCut: autoCut,
          openDrawer: openDrawer,
          drawerPin: drawerPin,
        ),
      );
    }

    await AppConfig.save(
      AppConfig(
        autoPrintEnabled: autoPrintEnabled,
        startAccessMode: startAccessMode,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Error BLE: $e")));
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

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
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

    final uuidInfo = (bleServiceUuid == null || bleCharUuid == null)
        ? "UUIDs de escritura: (no detectados)"
        : "Service: $bleServiceUuid\nChar: $bleCharUuid\nWithoutResponse: $bleWithoutResponse";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuración"),
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("❌ $e")));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _sectionCard(
            icon: Icons.language,
            title: "Acceso inicial",
            child: Column(
              children: [
                DropdownButtonFormField<StartAccessMode>(
                  initialValue: startAccessMode,
                  decoration: const InputDecoration(
                    labelText: "Abrir al iniciar",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<StartAccessMode>(
                      value: StartAccessMode.tienda,
                      child: Row(
                        children: [
                          Icon(Icons.storefront),
                          SizedBox(width: 10),
                          Text("Tienda"),
                        ],
                      ),
                    ),
                    DropdownMenuItem<StartAccessMode>(
                      value: StartAccessMode.puntoDeVenta,
                      child: Row(
                        children: [
                          Icon(Icons.point_of_sale),
                          SizedBox(width: 10),
                          Text("Punto de venta"),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => startAccessMode = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Impresión automática"),
                  subtitle: const Text("Usar impresión directa cuando aplique"),
                  value: autoPrintEnabled,
                  onChanged: (v) {
                    setState(() => autoPrintEnabled = v);
                  },
                ),
              ],
            ),
          ),
          _sectionCard(
            icon: Icons.print,
            title: "Modo de impresora",
            child: Column(
              children: [
                RadioListTile<PrinterMode>(
                  value: PrinterMode.tcp,
                  groupValue: mode,
                  title: const Text("Ethernet / Wi-Fi (TCP 9100)"),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => mode = v);
                    }
                  },
                ),
                RadioListTile<PrinterMode>(
                  value: PrinterMode.ble,
                  groupValue: mode,
                  title: const Text("Bluetooth BLE (iOS/Android)"),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => mode = v);
                    }
                  },
                ),
              ],
            ),
          ),
          if (mode == PrinterMode.tcp)
            _sectionCard(
              icon: Icons.wifi,
              title: "Configuración TCP",
              child: Column(
                children: [
                  TextField(
                    controller: hostCtrl,
                    decoration: const InputDecoration(
                      labelText: "IP / Host",
                      hintText: "192.168.1.118",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: portCtrl,
                    decoration: const InputDecoration(
                      labelText: "Puerto",
                      hintText: "9100",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          if (mode == PrinterMode.ble)
            _sectionCard(
              icon: Icons.bluetooth,
              title: "Configuración BLE",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "BLE: $currentBleName",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(uuidInfo),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _resolvingBle ? null : _pickBle,
                      icon: const Icon(Icons.search),
                      label: Text(
                        _resolvingBle ? "Buscando..." : "Buscar impresora",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _sectionCard(
            icon: Icons.receipt_long,
            title: "Formato de impresión",
            child: Column(
              children: [
                DropdownButtonFormField<PaperSizeMM>(
                  initialValue: selectedPaper,
                  decoration: const InputDecoration(
                    labelText: "Tamaño de papel",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<PaperSizeMM>(
                      value: PaperSizeMM.mm58,
                      child: Text("58 mm"),
                    ),
                    DropdownMenuItem<PaperSizeMM>(
                      value: PaperSizeMM.mm80,
                      child: Text("80 mm"),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => selectedPaper = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Corte automático"),
                  subtitle: const Text("Cortar ticket al finalizar"),
                  value: autoCut,
                  onChanged: (v) {
                    setState(() => autoCut = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Abrir cajón"),
                  subtitle: const Text("Enviar pulso al cajón al imprimir"),
                  value: openDrawer,
                  onChanged: (v) {
                    setState(() => openDrawer = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: drawerPin,
                  decoration: const InputDecoration(
                    labelText: "Pin del cajón",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<int>(value: 0, child: Text("Pin 2")),
                    DropdownMenuItem<int>(value: 1, child: Text("Pin 5")),
                  ],
                  onChanged: openDrawer
                      ? (v) {
                          if (v != null) {
                            setState(() => drawerPin = v);
                          }
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  final changedAccess =
                      startAccessMode != _originalStartAccessMode;

                  await _save();

                  if (!mounted) return;
                  Navigator.pop(context, changedAccess);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("❌ $e")));
                }
              },
              icon: const Icon(Icons.save),
              label: const Text("Guardar"),
            ),
          ),
        ],
      ),
    );
  }
}
