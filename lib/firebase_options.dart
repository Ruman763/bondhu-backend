// Generated from Firebase project bondhu-a6497 (google-services.json).
// For iOS/Web, run `flutterfire configure` and add GoogleService-Info.plist / web config.
// Note: iOS and web appId currently use ':placeholder' — FCM push will not work on those
// platforms until you run `flutterfire configure` and replace with real values.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBNc1yEPz_e54GSz4P8VM-PDua46IdGm38',
    appId: '1:870862996812:android:439276b7f9268c649abbe9',
    messagingSenderId: '870862996812',
    projectId: 'bondhu-a6497',
    storageBucket: 'bondhu-a6497.firebasestorage.app',
  );

  /// Replace with output of `flutterfire configure` for iOS.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBNc1yEPz_e54GSz4P8VM-PDua46IdGm38',
    appId: '1:870862996812:ios:placeholder',
    messagingSenderId: '870862996812',
    projectId: 'bondhu-a6497',
    storageBucket: 'bondhu-a6497.firebasestorage.app',
  );

  /// Bondhu 2.0 Web App (Firebase Console).
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBNc1yEPz_e54GSz4P8VM-PDua46IdGm38',
    appId: '1:870862996812:web:7d3958424c630e999abbe9',
    messagingSenderId: '870862996812',
    projectId: 'bondhu-a6497',
    storageBucket: 'bondhu-a6497.firebasestorage.app',
  );

  /// Web push: VAPID key from Firebase Console > Cloud Messaging > Web Push certificates.
  static const String webVapidKey = 'BLeG42oF5hoJ7HbaG6NkUMq_DPBj8Klc3rHyY3N87einu_A2oYtDMckLidPuL04cNvQnFlA0ghnklN-19N0D_gQ';
}
