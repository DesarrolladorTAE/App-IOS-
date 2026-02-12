import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _k = "app_config";

  final String baseUrl;
  final bool autoPrintEnabled;
  final String deviceId;

  const AppConfig({
    required this.baseUrl,
    required this.autoPrintEnabled,
    required this.deviceId,
  });

  Map<String, dynamic> toMap() => {
        "baseUrl": baseUrl,
        "autoPrintEnabled": autoPrintEnabled,
        "deviceId": deviceId,
      };

  static AppConfig fromMap(Map<String, dynamic> m) => AppConfig(
        baseUrl: m["baseUrl"] ?? "https://mitiendaenlineamx.com.mx/api",
        autoPrintEnabled: m["autoPrintEnabled"] ?? true,
        deviceId: m["deviceId"] ?? "",
      );

  static Future<AppConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);

    if (raw == null) {
      final id = "dev_${DateTime.now().millisecondsSinceEpoch}";
      final cfg = AppConfig(
        baseUrl: "https://mitiendaenlineamx.com.mx/api",
        autoPrintEnabled: true,
        deviceId: id,
      );
      await save(cfg);
      return cfg;
    }

    return fromMap(jsonDecode(raw));
  }

  static Future<void> save(AppConfig cfg) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(cfg.toMap()));
  }
}
