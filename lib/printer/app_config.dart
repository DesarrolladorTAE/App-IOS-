import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _k = "app_config";

  final bool autoPrintEnabled;

  const AppConfig({
    required this.autoPrintEnabled,
  });

  Map<String, dynamic> toMap() => {
        "autoPrintEnabled": autoPrintEnabled,
      };

  static AppConfig fromMap(Map<String, dynamic> m) => AppConfig(
        autoPrintEnabled: m["autoPrintEnabled"] ?? false,
      );

  static Future<AppConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);

    if (raw == null) {
      const cfg = AppConfig(
        autoPrintEnabled: false,
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