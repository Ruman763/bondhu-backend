/// Preset vibration pattern keys for chat notifications.
enum ChatVibrationPattern {
  default_,
  doubleTap,
  triple,
  long,
  shortLong,
}

extension ChatVibrationPatternExt on ChatVibrationPattern {
  /// [wait, vibrate, wait, vibrate, ...] in ms (Android).
  List<int> get durations {
    switch (this) {
      case ChatVibrationPattern.default_:
        return [0, 200];
      case ChatVibrationPattern.doubleTap:
        return [0, 150, 80, 150];
      case ChatVibrationPattern.triple:
        return [0, 100, 60, 100, 60, 100];
      case ChatVibrationPattern.long:
        return [0, 400];
      case ChatVibrationPattern.shortLong:
        return [0, 150, 100, 350];
    }
  }

  String get displayName {
    switch (this) {
      case ChatVibrationPattern.default_:
        return 'Default';
      case ChatVibrationPattern.doubleTap:
        return 'Double tap';
      case ChatVibrationPattern.triple:
        return 'Triple';
      case ChatVibrationPattern.long:
        return 'Long';
      case ChatVibrationPattern.shortLong:
        return 'Short–Long';
    }
  }
}
