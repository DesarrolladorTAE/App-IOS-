enum PrinterMode { tcp, ble, btClassic }

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

  // BT Classic (Android)
  final String? btMac;

  const PrinterConfig({
    required this.mode,
    this.host,
    this.port,
    this.bleDeviceId,
    this.bleDeviceName,
    this.bleServiceUuid,
    this.bleCharUuid,
    this.bleWithoutResponse,
    this.btMac,
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
        "btMac": btMac,
      };

  static PrinterConfig? fromMap(Map<String, dynamic> m) {
    final modeStr = m["mode"] as String?;
    if (modeStr == null) return null;

    final mode = PrinterMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => PrinterMode.tcp,
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
      btMac: m["btMac"] as String?,
    );
  }
}