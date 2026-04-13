import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum StartAccessMode { tienda, puntoDeVenta }

class AppConfig {
  static const _k = "app_config";

  static const String tiendaUrl =
      "https://mitiendaenlineamx.com.mx/login-register";

  static const String puntoDeVentaUrl =
      "https://mitiendaenlineamx.com.mx/prueba/pos";

  final bool autoPrintEnabled;
  final StartAccessMode startAccessMode;

  const AppConfig({
    required this.autoPrintEnabled,
    required this.startAccessMode,
  });

  AppConfig copyWith({
    bool? autoPrintEnabled,
    StartAccessMode? startAccessMode,
  }) {
    return AppConfig(
      autoPrintEnabled: autoPrintEnabled ?? this.autoPrintEnabled,
      startAccessMode: startAccessMode ?? this.startAccessMode,
    );
  }

  Map<String, dynamic> toMap() => {
    "autoPrintEnabled": autoPrintEnabled,
    "startAccessMode": startAccessMode.name,
  };

  static AppConfig fromMap(Map<String, dynamic> m) {
    final startAccessRaw = (m["startAccessMode"] ?? "").toString();

    final startAccessMode = StartAccessMode.values.firstWhere(
      (e) => e.name == startAccessRaw,
      orElse: () => StartAccessMode.tienda,
    );

    return AppConfig(
      autoPrintEnabled: m["autoPrintEnabled"] ?? false,
      startAccessMode: startAccessMode,
    );
  }

  static Future<AppConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);

    if (raw == null) {
      const cfg = AppConfig(
        autoPrintEnabled: false,
        startAccessMode: StartAccessMode.tienda,
      );
      await save(cfg);
      return cfg;
    }

    try {
      return fromMap(jsonDecode(raw));
    } catch (_) {
      const cfg = AppConfig(
        autoPrintEnabled: false,
        startAccessMode: StartAccessMode.tienda,
      );
      await save(cfg);
      return cfg;
    }
  }

  static Future<void> save(AppConfig cfg) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(cfg.toMap()));
  }

  static String urlForMode(StartAccessMode mode) {
    switch (mode) {
      case StartAccessMode.puntoDeVenta:
        return puntoDeVentaUrl;
      case StartAccessMode.tienda:
        return tiendaUrl;
    }
  }
}
