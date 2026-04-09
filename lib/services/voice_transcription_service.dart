import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_transcription_conversion_io.dart'
    if (dart.library.html) 'voice_transcription_conversion_web.dart' as conversion;

const String _prefKeyApiKey = 'bondhu_google_speech_api_key';

/// Transcribes voice message audio (from URL) to text using Google Cloud Speech-to-Text.
/// Requires a Google Cloud Speech-to-Text API key (set in Settings).
/// On mobile, M4A is converted to FLAC for the API; on web, conversion is not available.
class VoiceTranscriptionService {
  VoiceTranscriptionService._();
  static final VoiceTranscriptionService instance = VoiceTranscriptionService._();

  static const String _speechApiUrl = 'https://speech.googleapis.com/v1/speech:recognize';

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyApiKey);
  }

  Future<void> setApiKey(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.trim().isEmpty) {
      await prefs.remove(_prefKeyApiKey);
    } else {
      await prefs.setString(_prefKeyApiKey, value.trim());
    }
  }

  Future<bool> isAvailable() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Transcribe audio from a URL. Returns transcribed text or null on failure.
  Future<String?> transcribeFromUrl(
    String audioUrl, {
    String? languageCode,
  }) async {
    if (audioUrl.trim().isEmpty) return null;
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(audioUrl));
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;

      String? base64Audio;
      String encoding = 'FLAC';

      if (kIsWeb) {
        // Web: no FFmpeg; only FLAC URLs can be sent as-is.
        if (!audioUrl.split('?').first.toLowerCase().endsWith('.flac')) return null;
        base64Audio = base64Encode(bytes);
      } else {
        final flacBytes = await conversion.convertVoiceToFlac(bytes);
        if (flacBytes == null || flacBytes.isEmpty) return null;
        base64Audio = base64Encode(flacBytes);
      }

      if (base64Audio.isEmpty) return null;

      final lang = languageCode ?? 'en-US';
      final body = <String, dynamic>{
        'config': <String, dynamic>{
          'encoding': encoding,
          'languageCode': lang,
        },
        'audio': <String, dynamic>{'content': base64Audio},
      };

      final apiResponse = await http.post(
        Uri.parse('$_speechApiUrl?key=$apiKey'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (apiResponse.statusCode != 200) return null;
      final data = jsonDecode(apiResponse.body) as Map<String, dynamic>?;
      final results = data?['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final first = results.first;
      final alternatives = first is Map<String, dynamic> ? (first['alternatives'] as List<dynamic>?) : null;
      if (alternatives == null || alternatives.isEmpty) return null;
      final alt = alternatives.first;
      final transcript = alt is Map<String, dynamic> ? alt['transcript'] as String? : null;
      return transcript?.trim();
    } catch (_) {
      return null;
    }
  }
}
