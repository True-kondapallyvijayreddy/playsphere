import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseJsonService {
  static const String _storageKey = 'playsphere_production_state_v1';

  /// Load production JSON payload from asset or local persistence
  static Future<Map<String, dynamic>> loadProductionJsonData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJsonStr = prefs.getString(_storageKey);

      if (savedJsonStr != null && savedJsonStr.isNotEmpty) {
        return jsonDecode(savedJsonStr) as Map<String, dynamic>;
      }

      // Fallback: Read from assets/data/playsphere_production_seed.json
      final seedJsonStr = await rootBundle.loadString('assets/data/playsphere_production_seed.json');
      return jsonDecode(seedJsonStr) as Map<String, dynamic>;
    } catch (e) {
      // Emergency seed fallback
      return {
        'version': '1.0.0',
        'environment': 'production',
        'organizations': [],
        'competitions': [],
        'venues': [],
        'officials': [],
      };
    }
  }

  /// Persist mutated state to JSON storage
  static Future<void> saveProductionJsonData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(data);
      await prefs.setString(_storageKey, jsonStr);
    } catch (_) {}
  }

  /// Reset state back to initial seed data
  static Future<void> resetToSeedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
