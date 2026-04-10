/// Legacy Render chat server (only used if API is still localhost and CHAT_SERVER_URL is unset).
const String kProductionChatServerUrl = 'https://bondhu-chat-server.onrender.com';

/// Local backend port (bondhu-backend). Only used when CHAT_SERVER_URL is set to localhost.
const int kTestChatServerPort = 3000;

/// Chat / WebRTC signaling (Socket.IO). Prefer the **same host as [kApiBaseUrl]** so one VPS runs REST + realtime.
/// Override with: `--dart-define=CHAT_SERVER_URL=https://backend.example.com`
/// Local: `--dart-define=CHAT_SERVER_URL=http://localhost:3000` or `http://10.0.2.2:3000` (Android emulator)
String get kChatServerUrl {
  const override = String.fromEnvironment(
    'CHAT_SERVER_URL',
    defaultValue: '',
  );
  if (override.isNotEmpty) return override;
  final api = kApiBaseUrl.trim();
  if (api.isNotEmpty &&
      !api.contains('localhost') &&
      !api.contains('127.0.0.1') &&
      !api.contains('10.0.2.2')) {
    return api.endsWith('/') ? api.substring(0, api.length - 1) : api;
  }
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
