import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

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
    final gen = Generator(PaperSize.mm80, profile);

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
        throw Exception("BT clásico deshabilitado. Usa BLE o TCP.");
    }
  }

  // ---------------- PRINT JOB (payload desde SaaS) ----------------
  Future<void> printJob(Map<String, dynamic> payload) async {
    final cfg = await loadConfig();
    if (cfg == null) throw Exception("No hay impresora configurada");

    final bytes = await buildBytesFromJob(payload);

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
        throw Exception("BT clásico deshabilitado. Usa BLE o TCP.");
    }
  }

  // ---------------- JOB -> BYTES (drawer + logo + qr + cut) ----------------
  /// payload esperado (mínimo):
  /// {
  ///   "open_drawer": true,
  ///   "drawer_pin": 2,
  ///   "store_name": "Mi Tienda",
  ///   "address": "Calle ...",
  ///   "lines": [
  ///     {"text":"VENTA #123", "align":"center", "bold":true, "double":true},
  ///     {"hr":true},
  ///     {"text":"Producto X   1   $10.00", "align":"left"},
  ///   ],
  ///   "logo_url": "https://....png",
  ///   "qr": "https://....",
  ///   "cut": true
  /// }
  Future<List<int>> buildBytesFromJob(Map<String, dynamic> payload) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm80, profile);

    const int maxChars = 48;

    final bytes = <int>[];
    bytes.addAll(gen.reset());

    // Drawer
    if (payload["open_drawer"] == true) {
      final pin = (payload["drawer_pin"] as num?)?.toInt() ?? 2;
      bytes.addAll(
        gen.drawer(pin: (pin == 5) ? PosDrawer.pin5 : PosDrawer.pin2),
      );
      bytes.addAll(gen.feed(1));
    }

    // Logo
    final logoUrl = (payload["logo_url"] as String?)?.trim();
    if (logoUrl != null && logoUrl.isNotEmpty) {
      final logo = await _downloadAndPrepareImage(logoUrl, maxWidth: 560);
      if (logo != null) {
        bytes.addAll(gen.imageRaster(logo, align: PosAlign.center));
        bytes.addAll(gen.feed(1));
      }
    }

    // Store name + address
    final storeName = (payload["store_name"] as String?)?.trim();
    if (storeName != null && storeName.isNotEmpty) {
      bytes.addAll(
        gen.text(
          storeName,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    }

    final address = (payload["address"] as String?)?.trim();
    if (address != null && address.isNotEmpty) {
      for (final line in _wrap(address, maxChars)) {
        bytes.addAll(
          gen.text(line, styles: const PosStyles(align: PosAlign.center)),
        );
      }
    }

    bytes.addAll(gen.hr(ch: '-'));

    // Lines
    final lines = (payload["lines"] as List?) ?? const [];
    for (final it in lines) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it as Map);

      if (m["hr"] == true) {
        bytes.addAll(gen.hr(ch: '-'));
        continue;
      }

      final feed = (m["feed"] as num?)?.toInt();
      if (feed != null && feed > 0) {
        bytes.addAll(gen.feed(feed));
        continue;
      }

      final text = (m["text"] as String?) ?? "";
      if (text.isEmpty) continue;

      final align = _parseAlign((m["align"] as String?) ?? "left");
      final bold = m["bold"] == true;
      final dbl = m["double"] == true;

      bytes.addAll(
        gen.text(
          text,
          styles: PosStyles(
            align: align,
            bold: bold,
            height: dbl ? PosTextSize.size2 : PosTextSize.size1,
            width: dbl ? PosTextSize.size2 : PosTextSize.size1,
          ),
        ),
      );
    }

    // QR
    final qr = (payload["qr"] as String?)?.trim();
    if (qr != null && qr.isNotEmpty) {
      bytes.addAll(gen.feed(1));
      bytes.addAll(gen.qrcode(qr, align: PosAlign.center, size: QRSize.size6));
      bytes.addAll(gen.feed(1));
    }

    // Footer lines (opcional)
    final footer = (payload["footer"] as List?) ?? const [];
    for (final f in footer) {
      final txt = (f as String?)?.trim();
      if (txt == null || txt.isEmpty) continue;
      for (final line in _wrap(txt, maxChars)) {
        bytes.addAll(
          gen.text(line, styles: const PosStyles(align: PosAlign.center)),
        );
      }
    }

    bytes.addAll(gen.feed(2));

    final cut = payload["cut"] == null ? true : payload["cut"] == true;
    if (cut) bytes.addAll(gen.cut());

    return bytes;
  }

  PosAlign _parseAlign(String a) {
    switch (a.toLowerCase().trim()) {
      case "center":
        return PosAlign.center;
      case "right":
        return PosAlign.right;
      default:
        return PosAlign.left;
    }
  }

  List<String> _wrap(String text, int width) {
    final clean = text.replaceAll('\r', '').split('\n');
    final out = <String>[];

    for (final rawLine in clean) {
      var line = rawLine.trimRight();
      while (line.length > width) {
        out.add(line.substring(0, width));
        line = line.substring(width);
      }
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }

  Future<img.Image?> _downloadAndPrepareImage(
    String url, {
    required int maxWidth,
  }) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;

      final decoded = img.decodeImage(res.bodyBytes);
      if (decoded == null) return null;

      final resized = decoded.width > maxWidth
          ? img.copyResize(decoded, width: maxWidth)
          : decoded;
      final gray = img.grayscale(resized);
      return gray;
    } catch (_) {
      return null;
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

    // Si mandas imágenes por BLE y se corta, baja a 120
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
