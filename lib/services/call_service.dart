import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client_flutter/socket_io_client_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/app_config.dart';
import 'supabase_service.dart' show saveCallLog;
import 'chat_service.dart';
import 'custom_call_message_service.dart';

/// Asset path for incoming call ringtone (relative to assets/).
const String _incomingCallRingtoneAsset = 'sounds/incoming_call.mp3';

/// Call participant (remote user).
class CallUser {
  final String id;
  final String name;
  final String? avatar;
  CallUser({required this.id, required this.name, this.avatar});
}

/// Active call state (matches bondhu-v2 useRTC.js).
class ActiveCall {
  final CallUser user;
  final String type; // 'audio' | 'video'
  final String status; // 'dialing' | 'incoming' | 'connected'
  final bool isIncoming;
  ActiveCall({
    required this.user,
    required this.type,
    required this.status,
    required this.isIncoming,
  });
}

/// Custom voice/video message to play to the caller when callee did not answer.
class CustomCallMessagePlayback {
  final String calleeName;
  final String callType; // 'audio' | 'video'
  final String? voiceMessageUrl;
  final String? videoMessageUrl;
  CustomCallMessagePlayback({
    required this.calleeName,
    required this.callType,
    this.voiceMessageUrl,
    this.videoMessageUrl,
  });
  String? get urlToPlay =>
      callType == 'video' ? videoMessageUrl : voiceMessageUrl;
  bool get hasMessage => (urlToPlay ?? '').trim().isNotEmpty;
}

/// WebRTC call service: signaling via socket, live caption (speech_to_text + live_script_data).
/// Protocol matches bondhu-v2 useRTC.js and server (call_user, incoming_call, call_accepted, etc.).
class CallService {
  CallService({required this.chatService, this.onCallFailed, this.onCallEnded});

  final ChatService chatService;
  /// Called when a call fails (initiate or accept). UI should show a SnackBar with localized message.
  final void Function()? onCallFailed;
  /// Called when a call ends normally (user hung up or remote ended). UI can show a brief "Call ended" SnackBar.
  final void Function()? onCallEnded;

  /// Called when an incoming call is received. Set to show full-screen call notification when app is in background (e.g. like WhatsApp).
  void Function(String callerName, String callerId, String callType)? onShowIncomingCallNotification;

  /// When the caller receives call_declined with custom voice/video message URLs, this is set so UI can play the message. Clear after showing.
  final ValueNotifier<CustomCallMessagePlayback?> customMessageToPlayNotifier = ValueNotifier<CustomCallMessagePlayback?>(null);

  Socket? _socket;
  bool _listenersAttached = false;

  /// Set before each [onCallFailed] so UI can show a reason-specific message.
  /// Values: 'socket' | 'permission' | 'media' | 'ice' (or null for generic).
  String? _lastFailureReason;
  String? get lastCallFailureReason => _lastFailureReason;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  int? _callStartTime;

  final _activeCallController = ValueNotifier<ActiveCall?>(null);
  final _localStreamController = ValueNotifier<MediaStream?>(null);
  final _remoteStreamController = ValueNotifier<MediaStream?>(null);
  final _isAudioMutedController = ValueNotifier<bool>(false);
  final _isVideoMutedController = ValueNotifier<bool>(false);
  final _transcriptController = ValueNotifier<String>('');
  final _remoteTranscriptController = ValueNotifier<String>('');
  final _isLiveScriptEnabledController = ValueNotifier<bool>(false);
  final _isMinimizedController = ValueNotifier<bool>(false);

  ValueNotifier<ActiveCall?> get activeCallNotifier => _activeCallController;
  ValueNotifier<bool> get isMinimizedNotifier => _isMinimizedController;

  /// Call duration in seconds when connected; 0 otherwise.
  int get callDurationSeconds {
    if (_callStartTime == null) return 0;
    final cur = _activeCallController.value;
    if (cur == null || cur.status != 'connected') return 0;
    return ((DateTime.now().millisecondsSinceEpoch - _callStartTime!) / 1000).round();
  }
  ValueNotifier<MediaStream?> get localStreamNotifier => _localStreamController;
  ValueNotifier<MediaStream?> get remoteStreamNotifier => _remoteStreamController;
  ValueNotifier<bool> get isAudioMutedNotifier => _isAudioMutedController;
  ValueNotifier<bool> get isVideoMutedNotifier => _isVideoMutedController;
  ValueNotifier<String> get transcriptNotifier => _transcriptController;
  ValueNotifier<String> get remoteTranscriptNotifier => _remoteTranscriptController;
  ValueNotifier<bool> get isLiveScriptEnabledNotifier => _isLiveScriptEnabledController;
  bool _suppressNextCustomMessagePlayback = false;

  SpeechToText? _speech;
  bool _speechListening = false;
  Timer? _captionThrottleTimer;
  String _pendingCaptionText = '';
  static const _captionThrottleMs = 280;

  AudioPlayer? _ringtonePlayer;

  Timer? _disconnectedTimer;
  Timer? _failedTimer;
  bool _iceRestartTried = false;

  /// ICE servers: multiple STUN (free) for better NAT traversal + optional TURN from config for strict networks.
  static Map<String, dynamic> get _iceServers {
    final servers = <Map<String, String>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ];
    if (kTurnUrl.trim().isNotEmpty) {
      final turn = <String, String>{'urls': kTurnUrl.trim()};
      if (kTurnUsername.trim().isNotEmpty) turn['username'] = kTurnUsername.trim();
      if (kTurnCredential.trim().isNotEmpty) turn['credential'] = kTurnCredential.trim();
      servers.add(turn);
      // Extra relay paths improve reliability across strict NAT/firewalls.
      final rawTurn = kTurnUrl.trim();
      final hasHost = rawTurn.contains(':');
      final hostPort = rawTurn
          .replaceFirst(RegExp(r'^turns?:'), '')
          .split('?')
          .first
          .trim();
      if (hasHost && hostPort.isNotEmpty) {
        servers.add({
          'urls': 'turn:$hostPort?transport=tcp',
          if (kTurnUsername.trim().isNotEmpty) 'username': kTurnUsername.trim(),
          if (kTurnCredential.trim().isNotEmpty) 'credential': kTurnCredential.trim(),
        });
      }
    }
    return {'iceServers': servers};
  }

  static Map<String, dynamic> get _iceServersRelayOnly {
    final base = _iceServers;
    return <String, dynamic>{
      ...base,
      'iceTransportPolicy': 'relay',
    };
  }

  /// Optimized media constraints for stable, clear calls.
  /// - Audio: always request echo cancellation, noise suppression, auto gain.
  /// - Video: prioritize call stability over resolution (approx 640x360 @ 24fps).
  static Map<String, dynamic> _mediaConstraints(bool video) {
    // Web can use advanced media constraints; mobile prefers simple flags.
    if (!video) {
      if (kIsWeb) {
        return {
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        };
      }
      return {'audio': true, 'video': false};
    }

    if (kIsWeb) {
      return {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'width': {'ideal': 640, 'max': 960},
          'height': {'ideal': 360, 'max': 540},
          'frameRate': {'ideal': 24, 'max': 30},
          'facingMode': 'user',
        },
      };
    }

    return {
      'audio': true,
      'video': {
        'width': 640,
        'height': 360,
        'frameRate': 24,
        'facingMode': 'user',
      },
    };
  }

  static String _normId(String? s) => (s ?? '').toString().trim().toLowerCase();

  /// Normalize socket event payloads (Map or JSON string) into a Map.
  /// ChatService uses the same pattern for message events; this makes call
  /// signaling robust if the backend ever stringifies payloads.
  Map<String, dynamic>? _parseSocketPayload(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        // Ignore malformed JSON; caller will treat as null.
      }
    }
    return null;
  }

  /// Parse SDP offer/answer which may be sent as a Map, JSON string, or
  /// base64/base64url-encoded JSON. Returns null if structure is invalid.
  RTCSessionDescription? _parseSdpDescription(dynamic offer) {
    if (offer == null) return null;
    Map<String, dynamic>? map;
    if (offer is Map) {
      map = Map<String, dynamic>.from(offer);
    } else if (offer is String) {
      // Try plain JSON first
      try {
        final decoded = jsonDecode(offer);
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        }
      } catch (_) {
        // Then try base64 / base64url encoded JSON (similar to E2E payloads)
        try {
          String payloadJson;
          try {
            payloadJson = utf8.decode(base64.decode(offer));
          } catch (_) {
            final normalized = offer.replaceAll('-', '+').replaceAll('_', '/');
            final padding = (4 - normalized.length % 4) % 4;
            payloadJson = utf8.decode(base64.decode(normalized + ('=' * padding)));
          }
          final decoded = jsonDecode(payloadJson);
          if (decoded is Map<String, dynamic>) {
            map = decoded;
          }
        } catch (_) {}
      }
    }
    if (map == null) return null;
    final sdp = map['sdp']?.toString();
    final type = map['type']?.toString();
    if (sdp == null || type == null) return null;
    return RTCSessionDescription(sdp, type);
  }

  /// Request microphone (and camera for video) on mobile; on web skip (getUserMedia will prompt).
  /// Returns true if granted or running on web, false if denied.
  Future<bool> _requestCallPermissions(bool video) async {
    if (kIsWeb) return true;
    var mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (video) {
      var cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  String? get _userEmail => chatService.userEmail;
  String? get _userName => chatService.userName;

  /// Call when socket is available (e.g. when ChatService connectionStatus is connected).
  void attachSocket(Socket? socket) {
    if (socket == _socket) return;
    _removeListeners();
    _socket = socket;
    if (socket != null) _attachListeners();
  }

  void _attachListeners() {
    if (_socket == null || _listenersAttached) return;
    _listenersAttached = true;
    _socket!.on('incoming_call', _onIncomingCall);
    _socket!.on('call_accepted', _onCallAccepted);
    _socket!.on('call_candidate', _onCallCandidate);
    _socket!.on('end_call', _onEndCall);
    _socket!.on('call_declined', _onCallDeclined);
    _socket!.on('call_not_answered_message', _onCallNotAnsweredMessage);
    _socket!.on('call_history', _onCallHistory);
    _socket!.on('live_script_data', _onLiveScriptData);
    if (_pendingDeclineCallerId != null && _pendingDeclineCallerId!.isNotEmpty) {
      final id = _pendingDeclineCallerId!;
      _pendingDeclineCallerId = null;
      _emitDeclineWithCustomMessage(id);
    }
  }

  void _removeListeners() {
    if (_socket == null || !_listenersAttached) return;
    _listenersAttached = false;
    _socket!.off('incoming_call');
    _socket!.off('call_accepted');
    _socket!.off('call_candidate');
    _socket!.off('end_call', _onEndCall);
    _socket!.off('call_declined', _onCallDeclined);
    _socket!.off('call_not_answered_message', _onCallNotAnsweredMessage);
    _socket!.off('call_history');
    _socket!.off('live_script_data');
  }

  void _onIncomingCall(dynamic data) {
    final map = _parseSocketPayload(data);
    if (map == null) return;
    if (_activeCallController.value != null) return;
    final from = map['from'];
    final id = from is Map ? _normId(from['email']?.toString()) : _normId(map['from']?.toString());
    final name = from is Map ? (from['name']?.toString() ?? 'User') : 'User';
    final avatar = from is Map ? from['avatar']?.toString() : null;
    final type = map['type']?.toString() ?? 'audio';
    final offer = map['offer'];
    _pendingIncomingOffer = offer;
    _pendingIncomingEncryptedOffer = map['encryptedOffer'];
    _activeCallController.value = ActiveCall(
      user: CallUser(id: id, name: name, avatar: avatar),
      type: type,
      status: 'incoming',
      isIncoming: true,
    );
    onShowIncomingCallNotification?.call(name, id, type);
    // Respect per-chat call mute: if calls are muted for this chat, don't play ringtone.
    final mutedForCalls = chatService.isChatMutedForCalls(id);
    if (!mutedForCalls) {
      _startIncomingRingtone();
    }
  }

  Future<void> _startIncomingRingtone() async {
    await _stopIncomingRingtone();
    try {
      _ringtonePlayer ??= AudioPlayer();
      await _ringtonePlayer!.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer!.setSource(AssetSource(_incomingCallRingtoneAsset));
      await _ringtonePlayer!.resume();
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Ringtone start error: $e');
    }
  }

  Future<void> _stopIncomingRingtone() async {
    try {
      await _ringtonePlayer?.stop();
      await _ringtonePlayer?.release();
    } catch (_) {}
    _ringtonePlayer = null;
  }

  dynamic _pendingIncomingOffer;
  dynamic _pendingIncomingEncryptedOffer;

  /// When user taps "Decline" on call notification while app was killed; emit after socket connects.
  String? _pendingDeclineCallerId;

  /// Show incoming call UI from notification data (e.g. app was closed, user taps notification). No WebRTC offer yet.
  void showIncomingCallFromNotification(String callerId, String callerName, String callType) {
    if (_activeCallController.value != null) return;
    _activeCallController.value = ActiveCall(
      user: CallUser(id: callerId, name: callerName, avatar: null),
      type: callType,
      status: 'incoming',
      isIncoming: true,
    );
    _startIncomingRingtone();
  }

  /// Call when user declined from notification; we will emit call_declined once socket is connected.
  void setPendingDeclineFromNotification(String? callerId) {
    _pendingDeclineCallerId = callerId;
  }

  void _onCallAccepted(dynamic data) async {
    final map = _parseSocketPayload(data);
    if (map == null || _peerConnection == null) return;
    try {
      final desc = _parseSdpDescription(map['answer'] ?? map);
      if (desc == null) {
        if (kDebugMode) debugPrint('[CallService] _onCallAccepted: invalid answer payload: $map');
        return;
      }
      await _peerConnection!.setRemoteDescription(desc);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final cur = _activeCallController.value;
        if (cur != null) {
          _callStartTime ??= DateTime.now().millisecondsSinceEpoch;
          _activeCallController.value = ActiveCall(user: cur.user, type: cur.type, status: 'connected', isIncoming: cur.isIncoming);
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] setRemoteDescription error: $e');
    }
  }

  void _onCallCandidate(dynamic data) async {
    final map = _parseSocketPayload(data);
    if (map == null || _peerConnection == null) return;
    dynamic candidateData = map['candidate'] ?? map;
    Map<String, dynamic>? cMap;
    if (candidateData is Map) {
      cMap = Map<String, dynamic>.from(candidateData);
    } else if (candidateData is String) {
      try {
        final decoded = jsonDecode(candidateData);
        if (decoded is Map<String, dynamic>) {
          cMap = decoded;
        }
      } catch (_) {}
    }
    if (cMap == null) return;
    try {
      final idx = cMap['sdpMLineIndex'];
      final sdpMLineIndex = idx is int ? idx : (idx is num ? idx.toInt() : null);
      final c = RTCIceCandidate(
        cMap['candidate']?.toString(),
        cMap['sdpMid']?.toString(),
        sdpMLineIndex,
      );
      await _peerConnection!.addCandidate(c);
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] addCandidate error: $e');
    }
  }

  Future<void> _emitDeclineWithCustomMessage(String toId) async {
    final voiceUrl = await CustomCallMessageService.instance.getVoiceMessageUrl(toId);
    final videoUrl = await CustomCallMessageService.instance.getVideoMessageUrl(toId);
    final payload = <String, dynamic>{
      'to': toId,
      if ((voiceUrl ?? '').trim().isNotEmpty) 'voiceMessageUrl': voiceUrl!.trim(),
      if ((videoUrl ?? '').trim().isNotEmpty) 'videoMessageUrl': videoUrl!.trim(),
    };
    _socket?.emit('call_declined', payload);
  }

  /// Callee receives this when caller hung up. If we never answered, send our custom message to the caller.
  void _onEndCall(dynamic data) async {
    final cur = _activeCallController.value;
    if (cur != null && cur.isIncoming && cur.status == 'incoming') {
      final voiceUrl = await CustomCallMessageService.instance.getVoiceMessageUrl(cur.user.id);
      final videoUrl = await CustomCallMessageService.instance.getVideoMessageUrl(cur.user.id);
      final hasMessage = (voiceUrl ?? '').trim().isNotEmpty || (videoUrl ?? '').trim().isNotEmpty;
      if (hasMessage && _socket != null) {
        _socket!.emit('call_not_answered_message', {
          'to': cur.user.id,
          'calleeName': _userName ?? 'User',
          'callType': cur.type,
          if ((voiceUrl ?? '').trim().isNotEmpty) 'voiceMessageUrl': voiceUrl!.trim(),
          if ((videoUrl ?? '').trim().isNotEmpty) 'videoMessageUrl': videoUrl!.trim(),
        });
      }
    }
    endCall(emitEvent: false);
  }

  /// Caller receives this when callee declined. Server should forward payload with voiceMessageUrl / videoMessageUrl if set.
  void _onCallDeclined(dynamic data) {
    final cur = _activeCallController.value;
    final map = _parseSocketPayload(data);
    final voiceUrl = map?['voiceMessageUrl']?.toString();
    final videoUrl = map?['videoMessageUrl']?.toString();
    final hasCustomMessage = (voiceUrl ?? '').trim().isNotEmpty || (videoUrl ?? '').trim().isNotEmpty;
    if (cur != null && hasCustomMessage && !_suppressNextCustomMessagePlayback) {
      final playback = CustomCallMessagePlayback(
        calleeName: cur.user.name,
        callType: cur.type,
        voiceMessageUrl: (voiceUrl ?? '').trim().isEmpty ? null : voiceUrl,
        videoMessageUrl: (videoUrl ?? '').trim().isEmpty ? null : videoUrl,
      );
      _queueCustomMessagePlayback(playback);
    }
    _suppressNextCustomMessagePlayback = false;
    endCall(emitEvent: false);
  }

  /// Caller receives this when they hung up without the callee answering; server forwards callee's custom message.
  void _onCallNotAnsweredMessage(dynamic data) {
    final map = _parseSocketPayload(data);
    if (map == null) return;
    final calleeName = map['calleeName']?.toString() ?? 'User';
    final callType = map['callType']?.toString() ?? 'audio';
    final voiceUrl = map['voiceMessageUrl']?.toString();
    final videoUrl = map['videoMessageUrl']?.toString();
    final hasMessage = (voiceUrl ?? '').trim().isNotEmpty || (videoUrl ?? '').trim().isNotEmpty;
    if (hasMessage && !_suppressNextCustomMessagePlayback) {
      final playback = CustomCallMessagePlayback(
        calleeName: calleeName,
        callType: callType,
        voiceMessageUrl: (voiceUrl ?? '').trim().isEmpty ? null : voiceUrl,
        videoMessageUrl: (videoUrl ?? '').trim().isEmpty ? null : videoUrl,
      );
      _queueCustomMessagePlayback(playback);
    }
    _suppressNextCustomMessagePlayback = false;
  }

  void _queueCustomMessagePlayback(CustomCallMessagePlayback playback) {
    // Show after call UI fully dismisses for a smoother transition.
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      customMessageToPlayNotifier.value = playback;
    });
  }

  void _onCallHistory(dynamic data) {
    final map = _parseSocketPayload(data);
    if (map == null) return;
    final from = map['from']?.toString();
    final type = map['type']?.toString() ?? 'audio';
    final durationFormatted = map['durationFormatted']?.toString() ?? '';
    if (from == null) return;
    final chatId = _normId(from);
    chatService.addCallHistoryMessage(chatId, type, durationFormatted, false);
  }

  void _onLiveScriptData(dynamic data) {
    final map = _parseSocketPayload(data);
    if (map == null) return;
    final text = map['text']?.toString();
    if (text == null) return;
    _remoteTranscriptController.value = text;
  }

  void _cancelConnectionTimers() {
    _disconnectedTimer?.cancel();
    _disconnectedTimer = null;
    _failedTimer?.cancel();
    _failedTimer = null;
  }

  void _cleanupMedia() {
    _cancelConnectionTimers();
    _captionThrottleTimer?.cancel();
    _captionThrottleTimer = null;
    _pendingCaptionText = '';
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _peerConnection?.close();
    _peerConnection = null;
    _localStreamController.value = null;
    _remoteStreamController.value = null;
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '0:${seconds.toString().padLeft(2, '0')}';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Start voice or video call (initiator).
  Future<void> initiateCall(ChatItem chat, String type) async {
    _lastFailureReason = null;
    if (chat.id == 'group_global' || _activeCallController.value != null) return;
    if (_socket == null || !_socket!.connected) {
      if (kDebugMode) debugPrint('[CallService] initiateCall skipped: socket not connected');
      _lastFailureReason = 'socket';
      onCallFailed?.call();
      return;
    }
    _cleanupMedia();
    final video = type == 'video';
    if (!await _requestCallPermissions(video)) {
      _lastFailureReason = 'permission';
      onCallFailed?.call();
      return;
    }
    try {
      final constraints = _mediaConstraints(video);
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStreamController.value = _localStream;
      final pc = await _createPeerConnection(chat.id);
      if (pc == null) throw Exception('Failed to create peer connection');
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final payload = <String, dynamic>{
        'to': chat.id,
        'from': {'email': _userEmail, 'name': _userName, 'avatar': null},
        'type': type,
        'offer': offer.toMap(),
      };
      _socket?.emit('call_user', payload);
      _activeCallController.value = ActiveCall(
        user: CallUser(id: chat.id, name: chat.name, avatar: chat.avatar),
        type: type,
        status: 'dialing',
        isIncoming: false,
      );
      _isAudioMutedController.value = false;
      _isVideoMutedController.value = false;
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] initiateCall error: $e');
      _lastFailureReason = 'media';
      _cleanupMedia();
      _isMinimizedController.value = false;
      _activeCallController.value = null;
      onCallFailed?.call();
    }
  }

  Future<RTCPeerConnection?> _createPeerConnection(String targetId) async {
    _peerConnection?.close();
    _peerConnection = null;
    _iceRestartTried = false;
    final pc = await createPeerConnection(_iceServers);
    _peerConnection = pc;
    pc.onTrack = (event) {
      final streams = event.streams;
      if (streams.isNotEmpty) {
        _remoteStream = streams.first;
        // Ensure all audio tracks are enabled for playback
        for (final track in _remoteStream!.getAudioTracks()) {
          track.enabled = true;
        }
        // Ensure all video tracks are enabled
        for (final track in _remoteStream!.getVideoTracks()) {
          track.enabled = true;
        }
        _remoteStreamController.value = _remoteStream;
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          final cur = _activeCallController.value;
          if (cur != null) {
            _callStartTime ??= DateTime.now().millisecondsSinceEpoch;
            _activeCallController.value = ActiveCall(user: cur.user, type: cur.type, status: 'connected', isIncoming: cur.isIncoming);
          }
        });
      }
    };
    pc.onIceCandidate = (candidate) {
      _socket?.emit('call_candidate', {'target': targetId, 'candidate': candidate.toMap()});
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _cancelConnectionTimers();
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          final cur = _activeCallController.value;
          if (cur != null && cur.status != 'connected') {
            _callStartTime ??= DateTime.now().millisecondsSinceEpoch;
            _activeCallController.value = ActiveCall(user: cur.user, type: cur.type, status: 'connected', isIncoming: cur.isIncoming);
          }
        });
        _updateAudioRoute();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _disconnectedTimer?.cancel();
        _disconnectedTimer = null;
        if (_failedTimer?.isActive == true) return;
        _failedTimer = Timer(const Duration(seconds: 4), () {
          _failedTimer = null;
          if (!_iceRestartTried) {
            _iceRestartTried = true;
            _tryIceRestart(targetId);
            return;
          }
          if (kDebugMode) debugPrint('[CallService] Peer connection failed after grace period');
          _lastFailureReason = 'ice';
          endCall(emitEvent: false, showFailedMessage: true);
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _failedTimer?.cancel();
        _failedTimer = null;
        if (_disconnectedTimer?.isActive == true) return;
        _disconnectedTimer = Timer(const Duration(seconds: 12), () {
          _disconnectedTimer = null;
          if (!_iceRestartTried) {
            _iceRestartTried = true;
            _tryIceRestart(targetId);
            return;
          }
          if (kDebugMode) debugPrint('[CallService] Peer connection stayed disconnected, ending call');
          _lastFailureReason = 'ice';
          endCall(emitEvent: false, showFailedMessage: true);
        });
      }
    };
    return pc;
  }

  Future<void> _tryIceRestart(String _) async {
    final pc = _peerConnection;
    if (pc == null) return;
    try {
      if (kDebugMode) debugPrint('[CallService] trying ICE restart');
      // Prefer relay on restart for stability under poor networks/NAT.
      await pc.setConfiguration(_iceServersRelayOnly);
      await pc.restartIce();
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] ICE restart failed: $e');
    }
  }

  /// Accept incoming call.
  Future<void> acceptCall() async {
    final cur = _activeCallController.value;
    if (cur == null || cur.status != 'incoming') return;
    _lastFailureReason = null;
    await _stopIncomingRingtone();
    dynamic offer = _pendingIncomingOffer ?? _pendingIncomingEncryptedOffer;
    _pendingIncomingOffer = null;
    _pendingIncomingEncryptedOffer = null;
    if (offer == null) return;
    final video = cur.type == 'video';
    if (!await _requestCallPermissions(video)) {
      _lastFailureReason = 'permission';
      endCall(emitEvent: true);
      onCallFailed?.call();
      return;
    }
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints(video));
      _localStreamController.value = _localStream;
      final pc = await _createPeerConnection(cur.user.id);
      if (pc == null) return;
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
      final offerDesc = _parseSdpDescription(offer);
      if (offerDesc == null) {
        if (kDebugMode) debugPrint('[CallService] acceptCall: invalid offer payload: $offer');
        return;
      }
      await pc.setRemoteDescription(offerDesc);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _socket?.emit('call_accepted', {'to': cur.user.id, 'answer': answer.toMap()});
      _callStartTime = DateTime.now().millisecondsSinceEpoch;
      _activeCallController.value = ActiveCall(user: cur.user, type: cur.type, status: 'connected', isIncoming: true);
      _isAudioMutedController.value = false;
      _isVideoMutedController.value = false;
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] acceptCall error: $e');
      _lastFailureReason = 'media';
      endCall(emitEvent: true);
      onCallFailed?.call();
    }
  }

  /// Decline incoming call and optionally send custom voice/video message URLs so the caller can play them.
  Future<void> declineCall() async {
    _stopIncomingRingtone();
    final cur = _activeCallController.value;
    if (cur != null && cur.status == 'incoming') {
      final voiceUrl = await CustomCallMessageService.instance.getVoiceMessageUrl(cur.user.id);
      final videoUrl = await CustomCallMessageService.instance.getVideoMessageUrl(cur.user.id);
      final payload = <String, dynamic>{
        'to': cur.user.id,
        if ((voiceUrl ?? '').trim().isNotEmpty) 'voiceMessageUrl': voiceUrl!.trim(),
        if ((videoUrl ?? '').trim().isNotEmpty) 'videoMessageUrl': videoUrl!.trim(),
      };
      _socket?.emit('call_declined', payload);
    }
    endCall(emitEvent: false);
  }

  void toggleAudio() {
    if (_localStream == null) return;
    _isAudioMutedController.value = !_isAudioMutedController.value;
    final mute = _isAudioMutedController.value;
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = !mute;
    }
  }

  void toggleVideo() {
    if (_localStream == null) return;
    _isVideoMutedController.value = !_isVideoMutedController.value;
    final mute = _isVideoMutedController.value;
    for (final t in _localStream!.getVideoTracks()) {
      t.enabled = !mute;
    }
  }

  /// Switch front/back camera during a video call (mobile only).
  Future<void> switchCamera() async {
    if (kIsWeb) return;
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      try {
        await Helper.switchCamera(track);
        break;
      } catch (_) {
        // Ignore; fall through to next track or no-op.
      }
    }
  }

  /// Route audio: video calls use speakerphone, audio calls prefer earpiece (mobile only).
  Future<void> _updateAudioRoute() async {
    if (kIsWeb) return;
    final cur = _activeCallController.value;
    if (cur == null) return;
    final useSpeaker = cur.type == 'video';
    try {
      await Helper.setSpeakerphoneOn(useSpeaker);
    } catch (_) {
      // If routing fails, leave system default.
    }
  }

  void toggleLiveScript() {
    _isLiveScriptEnabledController.value = !_isLiveScriptEnabledController.value;
    if (_isLiveScriptEnabledController.value) {
      _startSpeechRecognition();
    } else {
      _stopSpeechRecognition();
    }
  }

  void setMinimized(bool value) {
    _isMinimizedController.value = value;
  }

  void toggleMinimize() {
    _isMinimizedController.value = !_isMinimizedController.value;
  }

  void setMinimizedTrue() => setMinimized(true);

  void _flushCaptionThrottle() {
    if (_pendingCaptionText.isEmpty) return;
    final cur = _activeCallController.value;
    if (cur != null && _socket != null) {
      _socket!.emit('live_script_data', {'target': cur.user.id, 'text': _pendingCaptionText});
    }
    _pendingCaptionText = '';
  }

  Future<void> _startSpeechRecognition() async {
    if (_speechListening) return;
    _speech ??= SpeechToText();
    final ok = await _speech!.initialize();
    if (!ok) return;
    _speechListening = true;
    await _speech!.listen(
      onResult: (result) {
        if (result.recognizedWords.isEmpty) return;
        _transcriptController.value = result.recognizedWords;
        _pendingCaptionText = result.recognizedWords;
        _captionThrottleTimer?.cancel();
        _captionThrottleTimer = Timer(const Duration(milliseconds: _captionThrottleMs), () {
          _flushCaptionThrottle();
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopSpeechRecognition() {
    _captionThrottleTimer?.cancel();
    _captionThrottleTimer = null;
    _flushCaptionThrottle();
    _speech?.stop();
    _speechListening = false;
    _transcriptController.value = '';
  }

  void endCall({bool emitEvent = true, bool showFailedMessage = false}) {
    if (showFailedMessage) onCallFailed?.call();
    _stopIncomingRingtone();
    final cur = _activeCallController.value;
    final wasConnected = cur?.status == 'connected';
    if (wasConnected) onCallEnded?.call();
    int durationSeconds = 0;
    if (_callStartTime != null && wasConnected) {
      durationSeconds = ((DateTime.now().millisecondsSinceEpoch - _callStartTime!) / 1000).round();
    }
    final durationFormatted = _formatDuration(durationSeconds);
    if (cur != null && wasConnected) {
      chatService.addCallHistoryMessage(cur.user.id, cur.type, durationFormatted, true);
      // Persist call history in DB (best effort) so it survives logout/device switch.
      final me = (_userEmail ?? '').trim().toLowerCase();
      final them = cur.user.id.trim().toLowerCase();
      if (me.isNotEmpty && them.isNotEmpty) {
        unawaited(saveCallLog(me, them, cur.type, durationSeconds));
      }
      if (emitEvent && _socket != null) {
        _socket!.emit('end_call', {'to': cur.user.id});
        _socket!.emit('call_history', {
          'to': cur.user.id,
          'from': _userEmail,
          'type': cur.type,
          'durationFormatted': durationFormatted,
        });
      }
    }
    _callStartTime = null;
    _cleanupMedia();
    _stopSpeechRecognition();
    _remoteTranscriptController.value = '';
    _transcriptController.value = '';
    _isLiveScriptEnabledController.value = false;
    _isAudioMutedController.value = false;
    _isVideoMutedController.value = false;
    _isMinimizedController.value = false;
    _activeCallController.value = null;
  }

  /// User-initiated end from call UI. This cancels one pending post-call custom playback.
  void endCallByUser() {
    _suppressNextCustomMessagePlayback = true;
    endCall();
  }

  void dispose() {
    _removeListeners();
    final player = _ringtonePlayer;
    _ringtonePlayer = null;
    player?.stop();
    player?.release();
    player?.dispose();
    endCall(emitEvent: false);
    _socket = null;
  }
}
