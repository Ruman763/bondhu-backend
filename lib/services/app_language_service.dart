import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';

const String _keyAppLanguage = 'bondhu_app_language';

/// App-wide language: English or Bangla. Controls full UI and voice-to-text locale.
class AppLanguageService extends ChangeNotifier {
  AppLanguageService._();
  static final AppLanguageService instance = AppLanguageService._();

  static const String en = 'en';
  static const String bn = 'bn';

  String _lang = en;
  bool _loaded = false;

  String get current => _lang;
  bool get isBangla => _lang == bn;

  Locale get locale => _lang == bn ? const Locale('bn', 'BD') : const Locale('en');
  /// Speech-to-text locale id (en or bn_BD).
  String get speechLocaleId => _lang == bn ? 'bn_BD' : 'en';

  String t(String key) => getAppString(key, _lang);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keyAppLanguage);
      if (value == bn) {
        _lang = bn;
      } else {
        _lang = en;
      }
    } catch (_) {
      _lang = en;
    }
    _loaded = true;
  }

  Future<void> setLanguage(String lang) async {
    if (lang != en && lang != bn) return;
    if (_lang == lang) return;
    _lang = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAppLanguage, _lang);
    } catch (_) {}
    notifyListeners();
  }
}
