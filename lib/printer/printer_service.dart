import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_config.dart';

class PrinterService {
  PrinterService._();
  static final instance = PrinterService._();

  static const _prefsKey = "printer_config";

  static const int cols58mm = 32;
  static const int cols80mm = 48;
  static const int dots58mm = 384;
  static const int dots80mm = 576;

  Future<void> saveConfig(PrinterConfig cfg) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, jsonEncode(cfg.toMap()));
    debugPrint("saveConfig -> ${jsonEncode(cfg.toMap())}");
  }

  Future<PrinterConfig?> loadConfig() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsKey);

    debugPrint("loadConfig -> raw: $raw");

    if (raw == null) return null;

    try {
      return PrinterConfig.fromMap(jsonDecode(raw));
    } catch (e) {
      debugPrint("loadConfig -> error parseando config: $e");
      return null;
    }
  }

  Future<void> printDemo() async {
    final cfg = await loadConfig();
    if (cfg == null) {
      throw Exception("No hay impresora configurada");
    }

    final paperSize = cfg.paperSize == PaperSizeMM.mm58 ? 58 : 80;

    final bytes = _buildTicket(
      paperSizeMm: paperSize,
      textBeforeQr:
          "PRUEBA SIMPLE\nMI TIENDA EN LINEAMX\nHOLA MUNDO\nTOTAL: \$123.85",
      textAfterQr: "Gracias por su compra",
      qrs: const [
        {
          "text": "https://mitiendaenlineamx.com.mx/facturacion-publica/demo",
          "size": 6,
          "caption": "Escanea para facturar",
          "align": "center",
          "ecc": 49,
        },
        {
          "text": "https://mitiendaenlineamx.com.mx",
          "size": 6,
          "caption": "Visita nuestra tienda",
          "align": "center",
          "ecc": 49,
        },
      ],
      cut: cfg.autoCut,
      shouldOpenDrawer: cfg.openDrawer,
      drawerPin: cfg.drawerPin,
      logoMaxWidth: paperSize == 58 ? 256 : 384,
    );

    await _sendToConfiguredPrinter(cfg, bytes);
  }

  Future<void> printJob(
    Map<String, dynamic> payload, {
    String? host,
    int? port,
  }) async {
    debugPrint("=== ENTRO A printJob CON BACKEND REAL ===");
    debugPrint("printJob -> payload keys: ${payload.keys.toList()}");
    debugPrint("printJob -> payload: $payload");

    final cfg = await loadConfig();

    final payloadPaper = payload["paper"] is Map
        ? Map<String, dynamic>.from(payload["paper"] as Map)
        : <String, dynamic>{};

    final int backendPaperSize =
        _readInt(payloadPaper["size"], fallback: 80) == 58 ? 58 : 80;

    final int localPaperSize = cfg?.paperSize == PaperSizeMM.mm58 ? 58 : 80;

    // Preferimos backend si viene válido
    final int paperSizeMm = (backendPaperSize == 58 || backendPaperSize == 80)
        ? backendPaperSize
        : localPaperSize;

    final textBeforeQr = _readString(payload["textBeforeQr"]);
    final textAfterQr = _readString(payload["textAfterQr"]);

    final imageBase64 = _firstNonEmptyString([
      payload["imageBase64"],
      payload["logo"],
      payload["logoBase64"],
      payload["image"],
      payload["logo_base64"],
      payload["image_base64"],
    ]);

    final cut = cfg != null
        ? cfg.autoCut
        : _readBool(payload["cut"], fallback: true);

    final shouldOpenDrawer = cfg != null
        ? cfg.openDrawer
        : _readBool(
            payload["shouldOpenDrawer"] ?? payload["openDrawer"],
            fallback: false,
          );

    final drawerPin = cfg != null
        ? cfg.drawerPin
        : _readInt(payload["drawerPin"], fallback: 0);

    final int maxDots = paperSizeMm == 58 ? dots58mm : dots80mm;

    final logoMaxWidth = _readInt(
      payload["logoMaxWidth"],
      fallback: paperSizeMm == 58 ? 256 : 384,
    ).clamp(64, maxDots);

    final qrs = _extractQrs(payload, fallbackPaperSize: paperSizeMm);

    final bytes = _buildTicket(
      paperSizeMm: paperSizeMm,
      textBeforeQr: textBeforeQr,
      textAfterQr: textAfterQr.isEmpty ? null : textAfterQr,
      imageBase64: imageBase64.isEmpty ? null : imageBase64,
      qrs: qrs,
      cut: cut,
      shouldOpenDrawer: shouldOpenDrawer,
      drawerPin: drawerPin,
      logoMaxWidth: logoMaxWidth,
    );

    debugPrint("printJob -> bytes generados: ${bytes.length}");

    if (host != null && host.trim().isNotEmpty) {
      await _printTcp(host: host.trim(), port: port ?? 9100, bytes: bytes);
      return;
    }

    if (cfg == null) {
      throw Exception("No hay impresora configurada");
    }

    await _sendToConfiguredPrinter(cfg, bytes);
  }

  List<Map<String, dynamic>> _extractQrs(
    Map<String, dynamic> payload, {
    required int fallbackPaperSize,
  }) {
    final result = <Map<String, dynamic>>[];

    final rawQrs = payload["qrs"];
    if (rawQrs is List) {
      for (final item in rawQrs) {
        if (item is Map) {
          final itemMap = Map<String, dynamic>.from(item);
          final text = _readString(itemMap["text"]).trim();
          if (text.isEmpty) continue;

          result.add({
            "text": text,
            "size": _readInt(
              itemMap["size"],
              fallback: fallbackPaperSize == 58 ? 5 : 7,
            ).clamp(1, 16),
            "caption": _readString(itemMap["caption"]),
            "align": _readString(itemMap["align"]).trim().isEmpty
                ? "center"
                : _readString(itemMap["align"]).trim().toLowerCase(),
            "ecc": _readInt(itemMap["ecc"], fallback: 49).clamp(48, 51),
          });
        }
      }
    }

    // Compatibilidad con payload viejo
    if (result.isEmpty) {
      final qrText = _readString(payload["qrText"]).trim();
      if (qrText.isNotEmpty) {
        result.add({
          "text": qrText,
          "size": _readInt(
            payload["qrSize"],
            fallback: fallbackPaperSize == 58 ? 5 : 7,
          ).clamp(1, 16),
          "caption": "",
          "align": "center",
          "ecc": _readInt(payload["qrEcc"], fallback: 49).clamp(48, 51),
        });
      }
    }

    return result;
  }

  Future<void> _sendToConfiguredPrinter(
    PrinterConfig cfg,
    List<int> bytes,
  ) async {
    debugPrint("_sendToConfiguredPrinter -> mode: ${cfg.mode}");

    switch (cfg.mode) {
      case PrinterMode.tcp:
        if (cfg.host == null || cfg.host!.trim().isEmpty) {
          throw Exception("No hay IP/host configurado para TCP");
        }

        await _printTcp(
          host: cfg.host!.trim(),
          port: cfg.port ?? 9100,
          bytes: bytes,
        );
        break;

      case PrinterMode.ble:
        if ((cfg.bleDeviceId ?? '').isEmpty ||
            (cfg.bleServiceUuid ?? '').isEmpty ||
            (cfg.bleCharUuid ?? '').isEmpty) {
          throw Exception("Configuración BLE incompleta");
        }

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

  List<int> _buildTicket({
    required int paperSizeMm,
    required String textBeforeQr,
    String? textAfterQr,
    bool cut = true,
    bool shouldOpenDrawer = false,
    int drawerPin = 0,
    String? imageBase64,
    List<Map<String, dynamic>> qrs = const [],
    int logoMaxWidth = 160,
  }) {
    final out = <int>[];

    out.addAll(_init());

    if (shouldOpenDrawer) {
      debugPrint("_buildTicket -> abrir cajón pin=$drawerPin");
      out.addAll(_drawerPulse(m: drawerPin, t1: 60, t2: 255));
      out.addAll(_lf(1));
      out.addAll(_drawerPulseAlt(m: drawerPin, t1: 60, t2: 255));
      out.addAll(_lf(1));
    }

    if (imageBase64 != null && imageBase64.trim().isNotEmpty) {
      debugPrint("_buildTicket -> imprimiendo logo");
      out.addAll(_alignCenter());
      out.addAll(_imageFromBase64(imageBase64, maxDotsWidth: logoMaxWidth));
      out.addAll(_lf(1));
      out.addAll(_alignLeft());
    }

    if (textBeforeQr.trim().isNotEmpty) {
      out.addAll(_alignLeft());
      out.addAll(_text(textBeforeQr));
      out.addAll(_lf(1));
    }

    for (final qr in qrs) {
      final text = _readString(qr["text"]).trim();
      if (text.isEmpty) continue;

      final size = _readInt(
        qr["size"],
        fallback: paperSizeMm == 58 ? 5 : 7,
      ).clamp(1, 16);

      final ecc = _readInt(qr["ecc"], fallback: 49).clamp(48, 51);
      final caption = _readString(qr["caption"]).trim();
      final align = _readString(qr["align"]).trim().toLowerCase();

      out.addAll(_setAlign(align));
      out.addAll(_qr(text, size: size, ecc: ecc));
      out.addAll(_lf(1));

      if (caption.isNotEmpty) {
        out.addAll(_setAlign(align));
        out.addAll(_text(caption));
        out.addAll(_lf(1));
      }

      out.addAll(_lf(1));
    }

    if (textAfterQr != null && textAfterQr.trim().isNotEmpty) {
      out.addAll(_alignLeft());
      out.addAll(_text(textAfterQr));
      out.addAll(_lf(1));
    }

    out.addAll(_lf(paperSizeMm == 58 ? 2 : 3));

    if (cut) {
      debugPrint("_buildTicket -> corte automático");
      out.addAll(_cutPartial());
    }

    return out;
  }

  List<int> _setAlign(String align) {
    switch (align) {
      case 'left':
        return _alignLeft();
      case 'right':
        return _alignRight();
      default:
        return _alignCenter();
    }
  }

  List<int> _init() => [0x1B, 0x40];

  List<int> _lf([int lines = 1]) {
    final count = lines <= 0 ? 1 : lines;
    return List<int>.filled(count, 0x0A);
  }

  List<int> _cutPartial() => [0x1D, 0x56, 0x42, 0x00];

  List<int> _alignLeft() => [0x1B, 0x61, 0x00];
  List<int> _alignCenter() => [0x1B, 0x61, 0x01];
  List<int> _alignRight() => [0x1B, 0x61, 0x02];

  List<int> _drawerPulse({int m = 0, int t1 = 60, int t2 = 255}) {
    return [0x1B, 0x70, m & 0xFF, t1 & 0xFF, t2 & 0xFF];
  }

  List<int> _drawerPulseAlt({int m = 0, int t1 = 60, int t2 = 255}) {
    return [0x1B, 0x70, (m == 0 ? 1 : 0) & 0xFF, t1 & 0xFF, t2 & 0xFF];
  }

  List<int> _text(String text) {
    final clean = _sanitizeText(
      text,
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return latin1.encode(clean);
  }

  List<int> _imageFromBase64(
    String base64OrDataUrl, {
    int maxDotsWidth = dots80mm,
  }) {
    try {
      final raw = base64OrDataUrl.trim();
      if (raw.isEmpty) {
        debugPrint("_imageFromBase64 -> vacío");
        return [];
      }

      final clean = raw.contains('base64,')
          ? raw.split('base64,').last.trim()
          : raw;

      final bytes = base64Decode(clean);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint("_imageFromBase64 -> no se pudo decodificar imagen");
        return [];
      }

      final scaled = _scaleImageToWidth(decoded, maxDotsWidth);
      return _bitmapToRasterEscPos(scaled);
    } catch (e) {
      debugPrint("_imageFromBase64 -> error: $e");
      return [];
    }
  }

  img.Image _scaleImageToWidth(img.Image src, int maxWidth) {
    if (src.width <= maxWidth) return src;

    final ratio = maxWidth / src.width;
    final h = (src.height * ratio).round().clamp(1, 100000);

    return img.copyResize(
      src,
      width: maxWidth,
      height: h,
      interpolation: img.Interpolation.average,
    );
  }

  List<int> _bitmapToRasterEscPos(img.Image bitmap) {
    final width = bitmap.width;
    final height = bitmap.height;

    final bytesPerRow = (width + 7) ~/ 8;
    final imageBytes = Uint8List(bytesPerRow * height);

    var idx = 0;
    for (var y = 0; y < height; y++) {
      for (var xByte = 0; xByte < bytesPerRow; xByte++) {
        var b = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xByte * 8 + bit;
          final pixelOn = x < width ? _isBlack(bitmap.getPixel(x, y)) : false;
          if (pixelOn) {
            b |= (0x80 >> bit);
          }
        }
        imageBytes[idx++] = b;
      }
    }

    final xL = bytesPerRow & 0xFF;
    final xH = (bytesPerRow >> 8) & 0xFF;
    final yL = height & 0xFF;
    final yH = (height >> 8) & 0xFF;

    return [0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH, ...imageBytes, 0x0A];
  }

  bool _isBlack(img.Pixel p) {
    final a = p.a.toInt();
    if (a < 128) return false;

    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();

    final lum = (0.299 * r + 0.587 * g + 0.114 * b);
    return lum < 180;
  }

  List<int> _qr(String content, {int size = 8, int ecc = 49}) {
    final data = utf8.encode(content);
    final out = <int>[];

    final s = size.clamp(1, 16);
    final e = ecc.clamp(48, 51);

    // Select model 2
    out.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // Module size
    out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, s]);

    // Error correction
    out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, e]);

    // Store data
    final len = data.length + 3;
    final pL = len & 0xFF;
    final pH = (len >> 8) & 0xFF;

    out.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    out.addAll(data);

    // Print QR
    out.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    out.add(0x0A);

    return out;
  }

  String _readString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  String _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final s = _readString(value).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _readBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;

    final s = (value?.toString() ?? '').trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;

    return fallback;
  }

  String _sanitizeText(String input) {
    return input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '-')
        .replaceAll('…', '...')
        .replaceAll('\t', '    ')
        .runes
        .where((r) => r == 10 || (r >= 32 && r <= 255))
        .map((r) => String.fromCharCode(r))
        .join();
  }

  Future<void> _printTcp({
    required String host,
    required int port,
    required List<int> bytes,
  }) async {
    Socket? socket;
    try {
      debugPrint("_printTcp -> conectando a $host:$port");
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );

      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 250));

      debugPrint("_printTcp -> bytes enviados: ${bytes.length}");
    } catch (e) {
      debugPrint("_printTcp -> error: $e");
      rethrow;
    } finally {
      await socket?.close();
    }
  }

  Future<void> _printBle({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
    required bool withoutResponse,
    required List<int> bytes,
  }) async {
    final device = ble.BluetoothDevice.fromId(deviceId);

    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
    } catch (_) {}

    try {
      final services = await device.discoverServices();

      final svc = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
      );

      final ch = svc.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == charUuid.toLowerCase(),
      );

      const chunkSize = 180;

      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize > bytes.length)
            ? bytes.length
            : i + chunkSize;

        await ch.write(
          Uint8List.fromList(bytes.sublist(i, end)),
          withoutResponse: withoutResponse,
        );

        await Future.delayed(const Duration(milliseconds: 30));
      }

      debugPrint("_printBle -> bytes enviados: ${bytes.length}");
    } catch (e) {
      debugPrint("_printBle -> error: $e");
      rethrow;
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}
