import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'encrypted_local_store.dart';
import 'message_sync_crypto_service.dart';
import 'push_notification_service.dart' show PushNotificationService;
import 'secure_storage_service.dart';

const String kAudienceDefault = 'public';
const String kAudiencePersonal = 'personal';
const String kAudienceWork = 'work';

// ====================================================
// Config — Local fallback backend
// ====================================================

const String _bucketId = 'media';
const String _localUserKey = 'bondhu_local_user';
const String _userPlaintextWipeDoneKey = 'bondhu_local_user_wipe_done';
const String _profilesStoreKey = 'bondhu_profiles_store_v1';
const String _accessTokenKey = 'bondhu_api_access_token';
const String _refreshTokenKey = 'bondhu_api_refresh_token';
const String _apiTimeoutError = 'Network timeout. Please try again.';

String defaultAvatar(String? userId) {
  if (userId == null || userId.isEmpty) return 'https://api.dicebear.com/7.x/avataaars/svg?seed=user';
  return 'https://api.dicebear.com/7.x/avataaars/svg?seed=${Uri.encodeComponent(userId)}';
}

List<String> parseContactList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String) {
    try {
      final decoded = jsonDecode(v) as List<dynamic>?;
      return decoded?.map((e) => e.toString()).toList() ?? [];
    } catch (_) {}
  }
  return [];
}

String contactListToString(List<String> arr) {
  final s = jsonEncode(arr);
  if (s.length <= 255) return s;
  final lastComma = s.lastIndexOf(',', 254);
  if (lastComma <= 0) return '[]';
  return '${s.substring(0, lastComma)}]';
}

Future<Map<String, Map<String, dynamic>>> _readProfilesStore() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesStoreKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final map = <String, Map<String, dynamic>>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        map[key] = Map<String, dynamic>.from(value);
      } else if (value is Map) {
        map[key] = value.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    return map;
  } catch (_) {
    return {};
  }
}

Future<void> _writeProfilesStore(Map<String, Map<String, dynamic>> store) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_profilesStoreKey, jsonEncode(store));
}

// ====================================================
// Models
// ====================================================

class AuthUser {
  final String? email;
  final String? name;
  final String? avatar;
  final String? docId;
  final String? bio;
  final String? location;
  final List<String> followers;
  final List<String> following;

  AuthUser({
    this.email,
    this.name,
    this.avatar,
    this.docId,
    this.bio,
    this.location,
    this.followers = const [],
    this.following = const [],
  });
}

class AudienceProfile {
  final String type; 
  final String? name;
  final String? bio;
  final String? avatar;
  final List<String> allowed;
  final List<String> denied;

  AudienceProfile({
    required this.type, 
    this.name, 
    this.bio, 
    this.avatar, 
    this.allowed = const [], 
    this.denied = const []
  });
  
  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'bio': bio,
        'avatar': avatar,
        'allowed': allowed,
        'denied': denied,
      };

  static AudienceProfile fromJson(Map<String, dynamic> j) => AudienceProfile(
        type: j['type'] as String? ?? 'public',
        name: j['name'] as String?,
        bio: j['bio'] as String?,
        avatar: j['avatar'] as String?,
        allowed: (j['allowed'] as List?)?.map((e) => e.toString()).toList() ?? [],
        denied: (j['denied'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

class ProfileDoc {
  final String docId;
  final String userId;
  final String name;
  final String avatar;
  final String? bio;
  final String? location;
  final List<String> followers;
  final List<String> following;
  final List<String> contactList;
  final String? publicKey;
  final String? e2eBackup;
  final String? e2eBackupSalt;
  final String? e2eBackupIterations;
  final Map<String, AudienceProfile> audienceProfiles;
  final String? messageCryptoSalt;

  ProfileDoc({
    required this.docId,
    required this.userId,
    this.name = '',
    this.avatar = '',
    this.bio,
    this.location,
    this.followers = const [],
    this.following = const [],
    this.contactList = const [],
    this.publicKey,
    this.e2eBackup,
    this.e2eBackupSalt,
    this.e2eBackupIterations,
    this.audienceProfiles = const {},
    this.messageCryptoSalt,
  });

  static ProfileDoc fromDoc(Map<String, dynamic> data) {
    Map<String, AudienceProfile> aud = {};
    final userId = data['user_id']?.toString() ?? data['email']?.toString() ?? '';
    final name = data['name']?.toString() ?? data['display_name']?.toString() ?? 'User';
    final avatar = data['avatar']?.toString() ?? data['avatar_url']?.toString() ?? '';
    final id = data['id']?.toString() ?? data['doc_id']?.toString() ?? userId;
    return ProfileDoc(
      docId: id,
      userId: userId,
      name: name,
      avatar: avatar,
      bio: data['bio']?.toString() ?? '',
      location: data['location'] as String?,
      followers: (data['followers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      following: (data['following'] as List?)?.map((e) => e.toString()).toList() ?? [],
      contactList: (data['contact_list'] as List?)?.map((e) => e.toString()).toList() ?? [],
      publicKey: data['public_key'] as String?,
      e2eBackup: data['e2e_backup'] as String?,
      e2eBackupSalt: data['e2e_backup_salt'] as String?,
      e2eBackupIterations: data['e2e_backup_iterations']?.toString(),
      audienceProfiles: aud,
      messageCryptoSalt: data['message_crypto_salt'] as String?,
    );
  }
}

class MessageDoc {
  final String id;
  final Map<String, dynamic> data;
  MessageDoc({required this.id, required this.data});
}

class PostDoc {
  final String docId;
  final String userId;
  final String timestamp;
  final String content;
  final String? mediaUrl;
  final String type;
  final List<String> likesList;
  final List<String> savedBy;
  final List<Map<String, dynamic>> comments;

  PostDoc({
    required this.docId,
    required this.userId,
    required this.timestamp,
    required this.content,
    this.mediaUrl,
    required this.type,
    required this.likesList,
    required this.savedBy,
    required this.comments,
  });

  static PostDoc fromDoc(Map<String, dynamic> data) {
    return PostDoc(
      docId: data['id']?.toString() ?? '',
      userId: data['author_id']?.toString() ?? '',
      timestamp: data['created_at']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      mediaUrl: data['media_url']?.toString(),
      type: data['type']?.toString() ?? 'text',
      likesList: (data['likes'] as List?)?.map((e) => e.toString()).toList() ?? [],
      savedBy: (data['saved_by'] as List?)?.map((e) => e.toString()).toList() ?? [],
      comments: (data['comments'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [],
    );
  }
}

class StoryItem {
  final String id;
  final String userId;
  final String userName;
  final String avatar;
  final String mediaUrl;
  final String time;
  final int timestamp;
  final List<String> likes;
  final List<Map<String, dynamic>> views;
  final List<String> comments;

  StoryItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.avatar,
    required this.mediaUrl,
    required this.time,
    required this.timestamp,
    List<String>? likes,
    List<Map<String, dynamic>>? views,
    List<String>? comments,
  })  : likes = likes ?? [],
        views = views ?? [],
        comments = comments ?? [];

  bool get isLikedBy => false;

  StoryItem copyWith({
    String? id,
    String? userId,
    String? userName,
    String? avatar,
    String? mediaUrl,
    String? time,
    int? timestamp,
    List<String>? likes,
    List<Map<String, dynamic>>? views,
    List<String>? comments,
  }) => StoryItem(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    userName: userName ?? this.userName,
    avatar: avatar ?? this.avatar,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    time: time ?? this.time,
    timestamp: timestamp ?? this.timestamp,
    likes: likes ?? this.likes,
    views: views ?? this.views,
    comments: comments ?? this.comments,
  );
}

// ====================================================
// Auth & User Lifecycle
// ====================================================

// Removed _getCurrentAuthUserId

String _normalizeApiBaseUrl(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
}

String get _apiBaseUrl => _normalizeApiBaseUrl(kApiBaseUrl);

Future<void> _saveTokens({
  required String accessToken,
  required String refreshToken,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_accessTokenKey, accessToken);
  await prefs.setString(_refreshTokenKey, refreshToken);
}

Future<String?> _getAccessToken() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_accessTokenKey);
  if (token == null || token.isEmpty) return null;
  return token;
}

Future<String?> _getRefreshToken() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_refreshTokenKey);
  if (token == null || token.isEmpty) return null;
  return token;
}

Future<void> _clearTokens() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_accessTokenKey);
  await prefs.remove(_refreshTokenKey);
}

Uri _apiUri(String path) {
  return Uri.parse('$_apiBaseUrl$path');
}

Never _throwApiError(http.Response response) {
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['error'] != null) {
      throw Exception(decoded['error'].toString());
    }
  } catch (_) {}
  throw Exception('Request failed (${response.statusCode})');
}

Future<Map<String, dynamic>> _refreshAccessTokenOrThrow() async {
  final refreshToken = await _getRefreshToken();
  if (refreshToken == null) {
    throw Exception('Session expired. Please log in again.');
  }
  try {
    final response = await http
        .post(
          _apiUri('/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = payload['accessToken']?.toString() ?? '';
      final newRefresh = payload['refreshToken']?.toString() ?? '';
      if (accessToken.isNotEmpty && newRefresh.isNotEmpty) {
        await _saveTokens(accessToken: accessToken, refreshToken: newRefresh);
      }
      return payload;
    }
    _throwApiError(response);
  } on TimeoutException {
    throw Exception(_apiTimeoutError);
  }
}

Future<http.Response> _authedGet(String path) async {
  final accessToken = await _getAccessToken();
  if (accessToken == null) throw Exception('Session expired. Please log in again.');

  Future<http.Response> doReq(String token) {
    return http.get(
      _apiUri(path),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 12));
  }

  try {
    var response = await doReq(accessToken);
    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessTokenOrThrow();
      final newToken = refreshed['accessToken']?.toString() ?? '';
      if (newToken.isNotEmpty) {
        response = await doReq(newToken);
      }
    }
    return response;
  } on TimeoutException {
    throw Exception(_apiTimeoutError);
  }
}

Future<http.Response> _authedPatch(String path, Map<String, dynamic> body) async {
  final accessToken = await _getAccessToken();
  if (accessToken == null) throw Exception('Session expired. Please log in again.');

  Future<http.Response> doReq(String token) {
    return http.patch(
      _apiUri(path),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 12));
  }

  try {
    var response = await doReq(accessToken);
    if (response.statusCode == 401) {
      final refreshed = await _refreshAccessTokenOrThrow();
      final newToken = refreshed['accessToken']?.toString() ?? '';
      if (newToken.isNotEmpty) {
        response = await doReq(newToken);
      }
    }
    return response;
  } on TimeoutException {
    throw Exception(_apiTimeoutError);
  }
}

AuthUser _authUserFromApi(Map<String, dynamic> userData) {
  final email = userData['email']?.toString() ?? '';
  final displayName = userData['display_name']?.toString();
  final avatar = userData['avatar_url']?.toString();
  final fallbackName = email.contains('@') ? email.split('@').first : 'user';
  return AuthUser(
    email: email,
    name: (displayName == null || displayName.isEmpty) ? fallbackName : displayName,
    avatar: (avatar == null || avatar.isEmpty) ? defaultAvatar(email) : avatar,
    docId: userData['id']?.toString(),
    bio: userData['bio']?.toString(),
    location: userData['location']?.toString(),
  );
}

Future<AuthUser?> getStoredUser() async {
  try {
    final user = await _getUserFromPrefs();
    if (user == null) return null;
    final prefAvatar = user.avatar;
    final profile = await syncProfile(user);
    if (profile != null) {
      try {
        await MessageSyncCryptoService.instance.ensureMessageVaultKey();
      } catch (_) {}
      final withProfile = AuthUser(
        email: user.email,
        name: user.name,
        avatar: profile.avatar.isNotEmpty ? profile.avatar : (prefAvatar ?? defaultAvatar(user.email)),
        docId: profile.docId,
        bio: profile.bio,
        location: profile.location,
        followers: profile.followers,
        following: profile.following,
      );
      await _saveUserToPrefs(withProfile);
      return withProfile;
    }
    return await _getUserFromPrefs();
  } catch (_) {
    return _getUserFromPrefs();
  }
}

Future<AuthUser?> _getUserFromPrefs() async {
  try {
    String? json;
    if (EncryptedLocalStore.instance.isReady) {
      json = await EncryptedLocalStore.instance.getString(_localUserKey);
    }
    if (json == null || json.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      json = prefs.getString(_localUserKey);
    }
    if (json == null || json.isEmpty) return null;
    final map = jsonDecode(json) as Map<String, dynamic>?;
    if (map == null) return null;
    final email = map['email'] as String? ?? '';
    final name = map['name'] as String? ?? email.split('@').first;
    if (email.isEmpty) return null;
    final rawAvatar = map['avatar'] as String?;
    final avatar = (rawAvatar != null && rawAvatar.isNotEmpty)
        ? rawAvatar
        : defaultAvatar(email);
    return AuthUser(
      email: email,
      name: name.isEmpty ? email.split('@').first : name,
      avatar: avatar,
      docId: map['docId'] as String?,
      bio: map['bio'] as String?,
      location: map['location'] as String?,
      followers: (map['followers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      following: (map['following'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  } catch (_) {
    return null;
  }
}

Future<void> _saveUserToPrefs(AuthUser user) async {
  try {
    final payload = jsonEncode({
      'email': user.email ?? '',
      'name': user.name ?? '',
      'avatar': user.avatar,
      'docId': user.docId,
      'bio': user.bio,
      'location': user.location,
      'followers': user.followers,
      'following': user.following,
    });
    final prefs = await SharedPreferences.getInstance();
    if (EncryptedLocalStore.instance.isReady) {
      await EncryptedLocalStore.instance.setString(_localUserKey, payload);
      if (prefs.getBool(_userPlaintextWipeDoneKey) != true) {
        await prefs.remove(_localUserKey);
        await prefs.setBool(_userPlaintextWipeDoneKey, true);
      }
    } else {
      await prefs.setString(_localUserKey, payload);
    }
  } catch (_) {}
}

Future<void> storeUser(AuthUser user) async {
  await _saveUserToPrefs(user);
}

Future<AuthUser?> getCachedUser() async {
  return _getUserFromPrefs();
}

Future<void> clearStoredUser() async {
  try {
    await _clearTokens();
    if (EncryptedLocalStore.instance.isReady) {
      await EncryptedLocalStore.instance.remove(_localUserKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localUserKey);
  } catch (_) {}
}

Future<AuthUser> signInWithEmail(String email, String password) async {
  final normalizedEmail = email.trim().toLowerCase();
  if (normalizedEmail.isEmpty || password.isEmpty) {
    throw Exception('Email and password are required.');
  }
  try {
    final response = await http
        .post(
          _apiUri('/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': normalizedEmail,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwApiError(response);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final user = payload['user'] as Map<String, dynamic>? ?? {};
    final accessToken = payload['accessToken']?.toString() ?? '';
    final refreshToken = payload['refreshToken']?.toString() ?? '';
    if (accessToken.isNotEmpty && refreshToken.isNotEmpty) {
      await _saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    }
    final authUser = _authUserFromApi(user);
    await storeUser(authUser);
    return authUser;
  } on TimeoutException {
    throw Exception(_apiTimeoutError);
  }
}

Future<AuthUser> signUpWithEmail(String email, String password, String name) async {
  final normalizedEmail = email.trim().toLowerCase();
  final n = name.trim().isEmpty ? normalizedEmail.split('@').first : name.trim();
  if (normalizedEmail.isEmpty || password.isEmpty) {
    throw Exception('Email and password are required.');
  }
  if (password.length < 8) {
    throw Exception('Password must be at least 8 characters long.');
  }
  try {
    final response = await http
        .post(
          _apiUri('/auth/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': normalizedEmail,
            'password': password,
            'name': n,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwApiError(response);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final user = payload['user'] as Map<String, dynamic>? ?? {};
    final accessToken = payload['accessToken']?.toString() ?? '';
    final refreshToken = payload['refreshToken']?.toString() ?? '';
    if (accessToken.isNotEmpty && refreshToken.isNotEmpty) {
      await _saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    }
    final authUser = _authUserFromApi(user);
    await storeUser(authUser);
    return authUser;
  } on TimeoutException {
    throw Exception(_apiTimeoutError);
  }
}

Future<AuthUser> signInWithGoogle() async {
  if (kIsWeb) {
    throw Exception('Google sign-in is currently mobile-only. Use email/password on web.');
  } else {
    if (kGoogleWebClientId.isEmpty) {
      throw Exception(
        'Missing GOOGLE_WEB_CLIENT_ID. Run with --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com',
      );
    }
    // Native approach
    final googleSignIn = GoogleSignIn(serverClientId: kGoogleWebClientId);
    final account = await googleSignIn.signIn();
    if (account == null) throw Exception('Google sign in cancelled');
    final auth = await account.authentication;
    if (auth.idToken == null || auth.accessToken == null) {
      throw Exception('Google token missing');
    }
    final response = await http
        .post(
          _apiUri('/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'idToken': auth.idToken}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwApiError(response);
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final user = payload['user'] as Map<String, dynamic>? ?? {};
    final accessToken = payload['accessToken']?.toString() ?? '';
    final refreshToken = payload['refreshToken']?.toString() ?? '';
    if (accessToken.isNotEmpty && refreshToken.isNotEmpty) {
      await _saveTokens(accessToken: accessToken, refreshToken: refreshToken);
    }
    final authUser = _authUserFromApi(user);
    await storeUser(authUser);
    return authUser;
  }
}

Future<bool> reauthenticateWithGoogle() async {
  try {
    await signInWithGoogle();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> verifyEmailAccountPassword(String email, String password) async {
  final normalized = email.trim().toLowerCase();
  if (normalized.isEmpty || password.isEmpty) return false;
  try {
    // Cannot easily silently verify in Supabase without affecting session
    // This is a placeholder until a dedicated re-auth flow is added.
    return true; 
  } catch (_) {
    return false;
  }
}

Future<AuthUser?> getCurrentUser() async {
  return _getUserFromPrefs();
}

Future<void> logout() async {
  try {
    final refreshToken = await _getRefreshToken();
    if (refreshToken != null) {
      await http
          .post(
            _apiUri('/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 8));
    }
    final token = PushNotificationService.instance.lastToken;
    if (token != null && token.isNotEmpty) {
      final email = (await _getUserFromPrefs())?.email;
      if (email != null) {
        await clearProfileFcmToken(email);
      }
    }
  } catch (_) {}
  await _clearTokens();
  await clearStoredUser();
  await SecureStorageService.instance.clearE2ESessionSecrets();
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
}

Future<void> updatePassword({required String oldPassword, required String newPassword}) async {
  if (newPassword.length < 8) {
    throw Exception('Password must be at least 8 characters long.');
  }
}

Future<void> sendPasswordResetEmail(String email) async {
  final normalizedEmail = email.trim().toLowerCase();
  if (normalizedEmail.isEmpty) {
    throw Exception('Email is required.');
  }
  try {
    final response = await http
        .post(
          _apiUri('/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': normalizedEmail}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwApiError(response);
    }
  } on TimeoutException {
    throw Exception(_apiTimeoutError);
  }
}

// ====================================================
// Profile Data
// ====================================================

Future<ProfileDoc?> syncProfile(AuthUser user) async {
  final email = (user.email ?? '').trim().toLowerCase();
  if (email.isEmpty) return null;

  try {
    final response = await _authedGet('/profile/me');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final me = payload['user'] as Map<String, dynamic>? ?? {};
      final mapped = <String, dynamic>{
        'id': me['id']?.toString(),
        'user_id': me['email']?.toString() ?? email,
        'name': me['display_name']?.toString() ?? user.name ?? email.split('@').first,
        'avatar': me['avatar_url']?.toString() ?? user.avatar ?? defaultAvatar(email),
        'bio': me['bio']?.toString(),
        'location': me['location']?.toString(),
        'followers': user.followers,
        'following': user.following,
        'contact_list': const <String>[],
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      final profiles = await _readProfilesStore();
      profiles[email] = mapped;
      await _writeProfilesStore(profiles);
      return ProfileDoc.fromDoc(mapped);
    }

    final profiles = await _readProfilesStore();
    final found = profiles[email];
    if (found != null) return ProfileDoc.fromDoc(found);
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = <String, dynamic>{
      'id': 'profile_$now',
      'user_id': email,
      'name': user.name ?? email.split('@').first,
      'avatar': user.avatar ?? defaultAvatar(email),
      'bio': 'New to Bondhu',
      'location': user.location,
      'followers': user.followers,
      'following': user.following,
      'contact_list': const <String>[],
      'created_at': now,
    };
    profiles[email] = created;
    await _writeProfilesStore(profiles);
    return ProfileDoc.fromDoc(created);
  } catch (e) {
    debugPrint('Sync profile err: $e');
    try {
      final profiles = await _readProfilesStore();
      final found = profiles[email];
      if (found != null) return ProfileDoc.fromDoc(found);
    } catch (_) {}
    return null;
  }
}

Future<ProfileDoc?> getProfileByUserId(String userId) async {
  final normalized = userId.trim().toLowerCase();
  try {
    final me = await _getUserFromPrefs();
    if (me != null && (me.email ?? '').trim().toLowerCase() == normalized) {
      final fresh = await syncProfile(me);
      if (fresh != null) return fresh;
    }
    final profiles = await _readProfilesStore();
    final res = profiles[normalized];
    if (res == null) return null;
    return ProfileDoc.fromDoc(res);
  } catch (_) {
    return null;
  }
}

Future<bool> followUnfollowViaFunction(String myEmail, String theirUserId, bool follow) async {
  return false;
}

Future<void> updateProfile(String docId, Map<String, dynamic> data) async {
  final mapped = <String, dynamic>{};
  if (data.containsKey('name')) mapped['displayName'] = data['name'];
  if (data.containsKey('avatar')) mapped['avatarUrl'] = data['avatar'];
  if (data.containsKey('bio')) mapped['bio'] = data['bio'];
  if (data.containsKey('location')) mapped['location'] = data['location'];

  try {
    if (mapped.isNotEmpty) {
      final response = await _authedPatch('/profile/me', mapped);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final me = await _getUserFromPrefs();
        if (me != null) {
          await syncProfile(me);
        }
        return;
      }
    }
  } catch (_) {}

  final profiles = await _readProfilesStore();
  String? userKey;
  Map<String, dynamic>? row;
  for (final entry in profiles.entries) {
    if ((entry.value['id']?.toString() ?? '') == docId) {
      userKey = entry.key;
      row = entry.value;
      break;
    }
  }
  if (userKey == null || row == null) return;
  row.addAll(data);
  profiles[userKey] = row;
  await _writeProfilesStore(profiles);
}

Future<void> updateProfileFcmToken(String userId, String token) async {
  final normalized = userId.trim().toLowerCase();
  final profile = await getProfileByUserId(normalized);
  if (profile != null) {
    await updateProfile(profile.docId, {'push_token': token});
  }
}

Future<void> clearProfileFcmToken(String userId) async {
  final normalized = userId.trim().toLowerCase();
  final profile = await getProfileByUserId(normalized);
  if (profile != null) {
    await updateProfile(profile.docId, {'push_token': null});
  }
}

Future<List<ProfileDoc>> searchProfiles(String queryText) async {
  final q = queryText.trim().toLowerCase();
  try {
    final profiles = await _readProfilesStore();
    final rows = profiles.values.where((row) {
      final name = (row['name']?.toString() ?? '').toLowerCase();
      final userId = (row['user_id']?.toString() ?? '').toLowerCase();
      return name.contains(q) || userId.contains(q);
    }).take(15);
    return rows.map((e) => ProfileDoc.fromDoc(e)).toList();
  } catch (_) {
    return [];
  }
}

Future<List<ProfileDoc>> getProfilesByIds(List<String> userIds) async {
  if (userIds.isEmpty) return [];
  try {
    final normalized = userIds.map((e) => e.trim().toLowerCase()).toSet();
    final profiles = await _readProfilesStore();
    return profiles.entries
        .where((e) => normalized.contains(e.key))
        .map((e) => ProfileDoc.fromDoc(e.value))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<List<ProfileDoc>> listRecentProfiles({int limit = 50}) async {
  try {
    final profiles = await _readProfilesStore();
    final rows = profiles.values.toList()
      ..sort((a, b) => (b['created_at'] as int? ?? 0).compareTo(a['created_at'] as int? ?? 0));
    return rows.take(limit).map((e) => ProfileDoc.fromDoc(e)).toList();
  } catch (_) {
    return [];
  }
}

// ====================================================
// Storage
// ====================================================

String storageFileViewUrl(String? fileId) {
  if (fileId == null || fileId.isEmpty) return '';
  if (fileId.startsWith('http://') || fileId.startsWith('https://')) return fileId;
  return fileId;
}

Future<String?> uploadFile(String path, {String? filename}) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return storageFileViewUrl(path);
  } catch (e) {
    return null;
  }
}

Future<String?> uploadFileFromBytes(List<int> bytes, String filename) async {
  try {
    if (bytes.isEmpty) return null;
    final tag = DateTime.now().millisecondsSinceEpoch;
    return storageFileViewUrl('local://$_bucketId/$tag-$filename');
  } catch (e) {
    return null;
  }
}

// ====================================================
// Posts
// ====================================================

Future<PostDoc> createPost({
  required String userId,
  required String content,
  String mediaUrl = '',
  String type = 'text',
}) async {
  final now = DateTime.now();
  return PostDoc(
    docId: 'post_${now.microsecondsSinceEpoch}',
    userId: userId,
    timestamp: now.toIso8601String(),
    content: content,
    mediaUrl: mediaUrl.isEmpty ? null : mediaUrl,
    type: type,
    likesList: const [],
    savedBy: const [],
    comments: const [],
  );
}

Future<List<dynamic>> getPosts({int limit = 50, int offset = 0}) async {
  // Returning dynamic list as stub
  return [];
}

Future<void> updatePost(String docId, Map<String, dynamic> data) async {}
Future<bool> deletePost(String docId) async { return true; }
Future<List<dynamic>> getPostsByIds(List<String> ids) async { return []; }

// ====================================================
// Stories
// ====================================================
Future<dynamic> createStory({required String userId, required String mediaUrl}) async {}
Future<List<dynamic>> getStories() async { return []; }
Future<void> deleteStory(String docId) async {}
Future<void> updateStory(String docId, Map<String, dynamic> data) async {}
List<StoryItem> storyDocumentsToItems(List<dynamic> docs, String? currentUserEmail) { return []; }

Future<List<String>> getContactUserIds(String userId) async {
  final p = await getProfileByUserId(userId);
  return p?.contactList ?? [];
}

Future<void> addContactToProfile(String myUserId, String contactUserId) async {
  // Stub
}

// ====================================================
// Queued messages
// ====================================================
Future<List<dynamic>> getQueuedMessages(String userEmail) async { return []; }
Future<void> deleteQueuedMessages(List<String> documentIds) async {}
Future<dynamic> sendToQueue({
  required String recipient,
  required String senderId,
  String senderName = '',
  required String payload,
  String msgId = '',
  String type = 'text',
}) async { return null; }

// ====================================================
// Chat Methods Mapping
// ====================================================
Future<dynamic> saveMessageToTable(String senderId, String receiverId, String payload, {String? timestamp}) async {}
Future<String?> uploadChatMigrationCipher({required String userId, required String cipher, Duration ttl = const Duration(minutes: 30)}) async { return null; }
Future<Map<String, dynamic>?> fetchChatMigrationDoc(String documentId) async { return null; }
Future<void> deleteChatMigrationDoc(String documentId) async {}
Future<bool> updateChatMigrationCipher({required String documentId, required String cipher}) async { return true; }

String audienceKeyFromFolder(String? folder) {
  if (folder == 'Personal') return kAudiencePersonal;
  if (folder == 'Work') return kAudienceWork;
  return kAudienceDefault;
}

extension ProfileDocAudience on ProfileDoc {
  String effectiveName(String audienceKey) {
    if (audienceKey == kAudienceDefault) return name;
    return audienceProfiles[audienceKey]?.name ?? name;
  }
  String effectiveAvatar(String audienceKey) {
    if (audienceKey == kAudienceDefault) return avatar;
    final a = audienceProfiles[audienceKey]?.avatar;
    return (a != null && a.isNotEmpty) ? a : avatar;
  }
  String? effectiveBio(String audienceKey) {
    if (audienceKey == kAudienceDefault) return bio;
    return audienceProfiles[audienceKey]?.bio ?? bio;
  }
}

// ====================================================
// Call Logs
// ====================================================
Future<void> saveCallLog(
  String callerId,
  String receiverId,
  String type,
  int duration,
) async {
  return;
}

// ====================================================
// Chat History
// ====================================================

Future<List<dynamic>> getChatHistory(String myId, String chatId, {int limit = 50, int offset = 0}) async {
  return [];
}
