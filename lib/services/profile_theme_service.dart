import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profile accent color / theme (for profile screen, QR, etc.).
class ProfileThemeService {
  ProfileThemeService._();
  static final ProfileThemeService instance = ProfileThemeService._();

  static const String _key = 'profile_theme_color';

  static const List<Color> presetColors = [
    Color(0xFF00C896), // Bondhu primary
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF06B6D4),
    Color(0xFF6366F1),
  ];

  final ValueNotifier<Color> accentColor = ValueNotifier<Color>(presetColors[0]);
  Future<SharedPreferences>? _prefsFuture;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    final value = prefs.getInt(_key);
    if (value != null) {
      accentColor.value = Color(value);
    }
  }

  Future<void> setAccentColor(Color color) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setInt(_key, color.toARGB32());
    accentColor.value = color;
  }
}
