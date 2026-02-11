import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';

class PrinterService {
  PrinterService._();
  static final instance = PrinterService._();

  static const _prefsKey = "printer_config";

  Future<void> saveConfig(PrinterConfig cfg) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, jsonEncode(cfg.toMap()));
  }

  Future<PrinterConfig?> loadConfig() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);
    if (raw == null) return null;
    return PrinterConfig.fromMap(jsonDecode(raw));
  }

  // ---------------- DEMO TICKET ----------------
  Future<List<int>> buildDemoTicketBytes() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);

    final bytes = <int>[];
    bytes.addAll(
      gen.text(
        "MI TIENDA EN LINEAMX",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(
      gen.text(
        "Prueba de impresión",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(gen.hr());
    bytes.addAll(gen.text("Fecha: ${DateTime.now()}"));
    bytes.addAll(
      gen.text("Total: \$123.45", styles: const PosStyles(bold: true)),
    );
    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());
    return bytes;
  }

  // ---------------- PRINT ENTRY ----------------
  Future<void> printDemo() async {
    final cfg = await loadConfig();
    if (cfg == null) throw Exception("No hay impresora configurada");

    final bytes = await buildDemoTicketBytes();

    switch (cfg.mode) {
      case PrinterMode.tcp:
        await _printTcp(host: cfg.host!, port: cfg.port ?? 9100, bytes: bytes);
        break;

      case PrinterMode.ble:
        await _printBle(
          deviceId: cfg.bleDeviceId!,
          serviceUuid: cfg.bleServiceUuid!,
          charUuid: cfg.bleCharUuid!,
          withoutResponse: cfg.bleWithoutResponse ?? true,
          bytes: bytes,
        );
        break;

      case PrinterMode.btClassic:
        throw Exception(
          "BT clásico deshabilitado (no compatible con iOS y rompe build). Usa BLE o TCP.",
        );
    }
  }

  // ---------------- TCP / ETHERNET ----------------
  Future<void> _printTcp({
    required String host,
    required int port,
    required List<int> bytes,
  }) async {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.add(Uint8List.fromList(bytes));
    await socket.flush();
    await socket.close();
  }

  // ---------------- BLE ----------------
  Future<void> _printBle({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
    required bool withoutResponse,
    required List<int> bytes,
  }) async {
    final device = ble.BluetoothDevice.fromId(deviceId);

    try {
      await device.connect(timeout: const Duration(seconds: 10));
    } catch (_) {}

    final services = await device.discoverServices();

    final svc = services.firstWhere(
      (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
    );

    final ch = svc.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase() == charUuid.toLowerCase(),
    );

    const chunkSize = 180;
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize > bytes.length) ? bytes.length : i + chunkSize;
      await ch.write(
        Uint8List.fromList(bytes.sublist(i, end)),
        withoutResponse: withoutResponse,
      );
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }
}
