import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN-protected hidden chats. User sets a PIN; chats added to "hidden" are excluded from the
/// main list and only visible after entering the PIN on the Hidden Chats screen.
class HiddenChatsService {
  HiddenChatsService._();
  static final HiddenChatsService instance = HiddenChatsService._();

  static const String _keyPinHash = 'hidden_chats_pin_hash';
  static const String _keyHiddenIds = 'hidden_chats_ids';
  static const String _keyBiometricEnabled = 'hidden_chats_biometric_enabled';
  static const String _salt = 'bondhu_hidden_pin_v1';

  final ValueNotifier<List<String>> hiddenIds = ValueNotifier<List<String>>([]);
  Future<SharedPreferences>? _prefsFuture;
  String _accountScope = 'global';

  static String _normAccount(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isEmpty ? 'global' : e;
  }

  String get _pinKey => '${_keyPinHash}_$_accountScope';
  String get _idsKey => '${_keyHiddenIds}_$_accountScope';
  String get _bioKey => '${_keyBiometricEnabled}_$_accountScope';

  Future<void> setAccountScope(String? email) async {
    final next = _normAccount(email);
    if (next == _accountScope) return;
    _accountScope = next;
    hiddenIds.value = [];
    await load();
  }

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    final raw = prefs.getString(_idsKey);
    if (raw == null || raw.isEmpty) {
      hiddenIds.value = [];
      return;
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => e as String)
          .where((id) => id.isNotEmpty)
          .toList();
      hiddenIds.value = list;
    } catch (_) {
      hiddenIds.value = [];
    }
  }

  Future<bool> hasPinSet() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final hash = prefs.getString(_pinKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Returns true if the PIN was set successfully. PIN should be 4–8 digits or similar.
  Future<bool> setPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.length < 4) return false;
    final hash = _hashPin(trimmed);
    if (hash == null) return false;
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setString(_pinKey, hash);
    return true;
  }

  /// Verifies the PIN; returns true if it matches the stored hash.
  Future<bool> verifyPin(String pin) async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final stored = prefs.getString(_pinKey);
    if (stored == null || stored.isEmpty) return false;
    final hash = _hashPin(pin.trim());
    return hash != null && hash == stored;
  }

  /// Change PIN: requires current PIN and new PIN. Returns true on success.
  Future<bool> changePin(String currentPin, String newPin) async {
    final ok = await verifyPin(currentPin);
    if (!ok) return false;
    return setPin(newPin);
  }

  /// Forgot-PIN recovery: removes PIN protection.
  /// For safety, this can also clear hidden chat IDs so old protected content is not exposed.
  Future<void> resetPin({bool clearHiddenChats = true}) async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.remove(_pinKey);
    await prefs.remove(_bioKey);
    if (clearHiddenChats) {
      hiddenIds.value = [];
      await prefs.remove(_idsKey);
    }
  }

  Future<bool> biometricEnabled() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    return prefs.getBool(_bioKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setBool(_bioKey, enabled);
  }

  static String? _hashPin(String pin) {
    try {
      final digest = SHA256Digest();
      final data = Uint8List.fromList(utf8.encode(pin + _salt));
      final result = digest.process(data);
      return base64Encode(result);
    } catch (e) {
      if (kDebugMode) debugPrint('[HiddenChats] hash error: $e');
      return null;
    }
  }

  bool isHidden(String chatId) {
    return hiddenIds.value.contains(chatId);
  }

  List<String> getHiddenIds() => List.from(hiddenIds.value);

  Future<void> addHidden(String chatId) async {
    if (chatId.isEmpty || hiddenIds.value.contains(chatId)) return;
    hiddenIds.value = List.from(hiddenIds.value)..add(chatId);
    await _saveIds();
  }

  Future<void> removeHidden(String chatId) async {
    if (!hiddenIds.value.contains(chatId)) return;
    hiddenIds.value = hiddenIds.value.where((id) => id != chatId).toList();
    await _saveIds();
  }

  Future<void> _saveIds() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setString(_idsKey, jsonEncode(hiddenIds.value));
  }
}
