/// On mobile we currently do not convert voice messages to FLAC.
/// Returning null causes transcription to fail gracefully (user sees error snackbar).
Future<List<int>?> convertVoiceToFlac(List<int> audioBytes) async {
  return null;
}

