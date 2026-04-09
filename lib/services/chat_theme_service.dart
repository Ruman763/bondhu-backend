import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for built-in chat background themes. [none] = default solid/dot background.
const String kChatThemeNone = 'none';
const String kChatThemeFlowers = 'flowers';
const String kChatThemeWinter = 'winter';
const String kChatThemeMilkyWay = 'milky_way';

const List<String> kChatThemeKeys = [kChatThemeNone, kChatThemeFlowers, kChatThemeWinter, kChatThemeMilkyWay];

/// Asset path for each theme (none has no asset).
/// Uses root-level chat_backgrounds/ so web does not request assets/assets/... (404).
String? chatThemeAsset(String key) {
  const base = 'chat_backgrounds';
  switch (key) {
    case kChatThemeFlowers:
      return '$base/flowers.png';
    case kChatThemeWinter:
      return '$base/winter.png';
    case kChatThemeMilkyWay:
      return '$base/milky_way.png';
    default:
      return null;
  }
}

/// Per-chat background theme. Persisted in SharedPreferences.
class ChatThemeService {
  ChatThemeService._();
  static final ChatThemeService instance = ChatThemeService._();

  static const String _prefix = 'chat_theme_';
  final ValueNotifier<int> _version = ValueNotifier<int>(0);
  ValueListenable<int> get version => _version;

  String _getKey(String chatId) => '$_prefix${chatId.trim().toLowerCase()}';

  /// Current background key for [chatId]. Returns [kChatThemeNone] if unset.
  Future<String> getChatBackground(String chatId) async {
    if (chatId.isEmpty) return kChatThemeNone;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_getKey(chatId)) ?? kChatThemeNone;
    } catch (_) {
      return kChatThemeNone;
    }
  }

  /// Sync get for use in build (uses cached value; call [load] first or use default).
  String _cache = kChatThemeNone;
  String get cachedTheme => _cache;

  /// Set background for [chatId] and notify listeners.
  Future<void> setChatBackground(String chatId, String themeKey) async {
    if (chatId.isEmpty) return;
    if (!kChatThemeKeys.contains(themeKey)) themeKey = kChatThemeNone;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_getKey(chatId), themeKey);
      _cache = themeKey;
      _version.value++;
    } catch (_) {}
  }
}

