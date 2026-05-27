enum PrinterMode { tcp, ble, usb, btClassic }

enum PaperSizeMM { mm58, mm80 }

class PrinterConfig {
  final PrinterMode mode;

  // TCP
  final String? host;
  final int? port;

  // BLE
  final String? bleDeviceId;
  final String? bleDeviceName;
  final String? bleServiceUuid;
  final String? bleCharUuid;
  final bool? bleWithoutResponse;

  // USB Android
  final int? usbVendorId;
  final int? usbProductId;
  final String? usbDeviceName;

  // BT Classic futuro
  final String? btMac;

  final PaperSizeMM paperSize;
  final bool autoCut;
  final bool openDrawer;
  final int drawerPin;

  const PrinterConfig({
    required this.mode,
    this.host,
    this.port,
    this.bleDeviceId,
    this.bleDeviceName,
    this.bleServiceUuid,
    this.bleCharUuid,
    this.bleWithoutResponse,
    this.usbVendorId,
    this.usbProductId,
    this.usbDeviceName,
    this.btMac,
    this.paperSize = PaperSizeMM.mm80,
    this.autoCut = true,
    this.openDrawer = false,
    this.drawerPin = 0,
  });

  Map<String, dynamic> toMap() => {
        "mode": mode.name,
        "host": host,
        "port": port,
        "bleDeviceId": bleDeviceId,
        "bleDeviceName": bleDeviceName,
        "bleServiceUuid": bleServiceUuid,
        "bleCharUuid": bleCharUuid,
        "bleWithoutResponse": bleWithoutResponse,
        "usbVendorId": usbVendorId,
        "usbProductId": usbProductId,
        "usbDeviceName": usbDeviceName,
        "btMac": btMac,
        "paperSize": paperSize.name,
        "autoCut": autoCut,
        "openDrawer": openDrawer,
        "drawerPin": drawerPin,
      };

  static PrinterConfig? fromMap(Map<String, dynamic> m) {
    final modeStr = m["mode"] as String?;
    if (modeStr == null) return null;

    final mode = PrinterMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => PrinterMode.tcp,
    );

    final paperSizeStr = m["paperSize"] as String?;
    final paperSize = PaperSizeMM.values.firstWhere(
      (e) => e.name == paperSizeStr,
      orElse: () => PaperSizeMM.mm80,
    );

    return PrinterConfig(
      mode: mode,
      host: m["host"] as String?,
      port: (m["port"] as num?)?.toInt(),
      bleDeviceId: m["bleDeviceId"] as String?,
      bleDeviceName: m["bleDeviceName"] as String?,
      bleServiceUuid: m["bleServiceUuid"] as String?,
      bleCharUuid: m["bleCharUuid"] as String?,
      bleWithoutResponse: m["bleWithoutResponse"] as bool?,
      usbVendorId: (m["usbVendorId"] as num?)?.toInt(),
      usbProductId: (m["usbProductId"] as num?)?.toInt(),
      usbDeviceName: m["usbDeviceName"] as String?,
      btMac: m["btMac"] as String?,
      paperSize: paperSize,
      autoCut: m["autoCut"] as bool? ?? true,
      openDrawer: m["openDrawer"] as bool? ?? false,
      drawerPin: (m["drawerPin"] as num?)?.toInt() ?? 0,
    );
  }
}