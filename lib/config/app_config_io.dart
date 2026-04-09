import 'dart:io';

/// On Android emulator, localhost is the emulator; use 10.0.2.2 to reach host machine.
String get defaultTestChatHost =>
    Platform.isAndroid ? '10.0.2.2' : 'localhost';
