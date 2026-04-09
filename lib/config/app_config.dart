/// Same server for both platforms (web + app). Single source: ../bondhu-chat-server-url.txt
/// Website: bondhu-v2 .env VITE_SOCKET_URL — keep this value in sync.
const String kProductionChatServerUrl = 'https://bondhu-chat-server.onrender.com';

/// Local backend port (bondhu-backend). Only used when CHAT_SERVER_URL is set to localhost.
const int kTestChatServerPort = 3000;

/// Chat server URL. Uses production server by default (debug and release) so chat works without a local server.
/// To test against a local backend, run with: flutter run --dart-define=CHAT_SERVER_URL=http://localhost:3000
/// (or http://10.0.2.2:3000 on Android emulator)
String get kChatServerUrl {
  const override = String.fromEnvironment(
    'CHAT_SERVER_URL',
    defaultValue: '',
  );
  if (override.isNotEmpty) return override;
  return kProductionChatServerUrl;
}

/// True when using a local/test backend (localhost, 10.0.2.2, 127.0.0.1).
bool get kUseTestChatServer =>
    kChatServerUrl.contains('localhost') ||
    kChatServerUrl.contains('10.0.2.2') ||
    kChatServerUrl.contains('127.0.0.1');

/// Optional TURN server for stable calls across NAT/firewalls. Leave empty to use STUN only.
/// Set via: flutter run --dart-define=TURN_URL=turn:your-server:3478 --dart-define=TURN_USER=user --dart-define=TURN_CRED=pass
///
/// Defaults below point to your VPS TURN so calling remains stable even without
/// passing dart-defines at runtime.
const String kTurnUrl = String.fromEnvironment('TURN_URL', defaultValue: 'turn:167.86.79.126:3478?transport=udp');
const String kTurnUsername = String.fromEnvironment('TURN_USER', defaultValue: 'admin');
const String kTurnCredential = String.fromEnvironment('TURN_CRED', defaultValue: 'Ruman.787');

/// Google Web OAuth client ID used as server client ID for native token exchange.
/// Set via: --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
const String kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);

/// REST API URL for VPS backend auth/profile endpoints.
/// Override with: --dart-define=API_BASE_URL=http://your-server:3000
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
