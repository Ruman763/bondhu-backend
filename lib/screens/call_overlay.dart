import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/call_service.dart';

/// Isolated caption strip so transcript updates don't rebuild the full call overlay.
class _CaptionStrip extends StatelessWidget {
  const _CaptionStrip({
    required this.remoteName,
    required this.remoteTranscriptNotifier,
    required this.transcriptNotifier,
  });

  final String remoteName;
  final ValueNotifier<String> remoteTranscriptNotifier;
  final ValueNotifier<String> transcriptNotifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: remoteTranscriptNotifier,
          builder: (context, remoteTranscript, _) {
            if (remoteTranscript.isEmpty) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(remoteName, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: BondhuTokens.primary, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(remoteTranscript, style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.white)),
                ],
              ),
            );
          },
        ),
        ValueListenableBuilder<String>(
          valueListenable: transcriptNotifier,
          builder: (context, transcript, _) {
            if (transcript.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: BondhuTokens.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BondhuTokens.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppLanguageService.instance.t('you'), style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(transcript, style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.white)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Minimized call bar: shows at bottom so user can keep using the app while in a call (background call).
class _MinimizedCallBar extends StatefulWidget {
  const _MinimizedCallBar({
    required this.callService,
    required this.call,
    required this.isDark,
  });

  final CallService callService;
  final ActiveCall call;
  final bool isDark;

  @override
  State<_MinimizedCallBar> createState() => _MinimizedCallBarState();
}

class _MinimizedCallBarState extends State<_MinimizedCallBar> {
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    if (widget.call.status == 'connected') _startDurationTimer();
  }

  @override
  void didUpdateWidget(covariant _MinimizedCallBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.call.status == 'connected' && _durationTimer == null) _startDurationTimer();
    if (widget.call.status != 'connected' && _durationTimer != null) _durationTimer?.cancel();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final durationSec = call.status == 'connected' ? widget.callService.callDurationSeconds : 0;
    final subtitle = call.status == 'incoming'
        ? 'Incoming'
        : call.status == 'connected'
            ? 'In call · ${_formatDuration(durationSec)}'
            : 'Connecting...';

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              color: widget.isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => widget.callService.setMinimized(false),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: BondhuTokens.primary.withValues(alpha: 0.3),
                        backgroundImage: call.user.avatar != null && call.user.avatar!.isNotEmpty ? NetworkImage(call.user.avatar!) : null,
                        child: call.user.avatar == null || call.user.avatar!.isEmpty ? Icon(Icons.person, color: BondhuTokens.primary, size: 28) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              call.user.name,
                              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              subtitle,
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: BondhuTokens.primary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_full_rounded, color: Colors.white70),
                        onPressed: () => widget.callService.setMinimized(false),
                        tooltip: 'Expand call',
                      ),
                      Material(
                        color: Colors.red,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () => widget.callService.endCall(),
                          customBorder: const CircleBorder(),
                          child: const SizedBox(width: 44, height: 44, child: Icon(Icons.call_end_rounded, color: Colors.white, size: 22)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen call UI: incoming (accept/decline), connected (video/audio, mute, live caption, end).
class CallOverlay extends StatefulWidget {
  const CallOverlay({
    super.key,
    required this.callService,
    required this.isDark,
  });

  final CallService callService;
  final bool isDark;

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  OverlayEntry? _overlayEntry;
  /// When root overlay is null, show call UI in-place instead of via OverlayEntry.
  bool _showInPlace = false;

  @override
  void initState() {
    super.initState();
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _localRenderer!.initialize().then((_) => _updateRenderers());
    _remoteRenderer!.initialize().then((_) => _updateRenderers());
    widget.callService.localStreamNotifier.addListener(_updateRenderers);
    widget.callService.remoteStreamNotifier.addListener(_updateRenderers);
    widget.callService.activeCallNotifier.addListener(_onCallStateChanged);
    _onCallStateChanged();
  }

  void _onCallStateChanged() {
    final activeCall = widget.callService.activeCallNotifier.value;
    if (activeCall != null && _overlayEntry == null && !_showInPlace) {
      // Insert overlay entry into root navigator's overlay
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final overlay = Navigator.of(context, rootNavigator: true).overlay;
        if (overlay != null) {
          _overlayEntry = OverlayEntry(
            builder: (context) => _buildOverlayContent(),
            maintainState: true,
          );
          overlay.insert(_overlayEntry!);
        } else if (mounted) {
          // Fallback: root overlay unavailable (e.g. some test or route setup); show in place
          setState(() => _showInPlace = true);
        }
      });
    } else if (activeCall == null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (_showInPlace && mounted) setState(() => _showInPlace = false);
    } else if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    } else if (_showInPlace && mounted) {
      setState(() {});
    }
  }

  void _updateRenderers() {
    if (!mounted) return;
    final local = widget.callService.localStreamNotifier.value;
    final remote = widget.callService.remoteStreamNotifier.value;
    if (_localRenderer != null) _localRenderer!.srcObject = local;
    if (_remoteRenderer != null) _remoteRenderer!.srcObject = remote;
    _overlayEntry?.markNeedsBuild();
  }

  @override
  void dispose() {
    widget.callService.localStreamNotifier.removeListener(_updateRenderers);
    widget.callService.remoteStreamNotifier.removeListener(_updateRenderers);
    widget.callService.activeCallNotifier.removeListener(_onCallStateChanged);
    _overlayEntry?.remove();
    _overlayEntry = null;
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  Widget _buildOverlayContent() {
    return ValueListenableBuilder<ActiveCall?>(
      valueListenable: widget.callService.activeCallNotifier,
      builder: (context, activeCall, _) {
        if (activeCall == null) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: widget.callService.isMinimizedNotifier,
          builder: (context, isMinimized, _) {
            if (isMinimized) {
              return _MinimizedCallBar(
                callService: widget.callService,
                call: activeCall,
                isDark: widget.isDark,
              );
            }
            return Material(
              color: Colors.transparent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Full screen call UI
                  _buildFullCallUI(activeCall),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFullCallUI(ActiveCall activeCall) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildRemoteVideo(activeCall),
            if (activeCall.status == 'connected') _buildLocalVideo(activeCall),
            _buildTopBar(activeCall),
            _buildCaptionOverlay(activeCall),
            _buildBottomBar(activeCall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When overlay insert failed, show call UI in place so the call is still visible
    if (_showInPlace && widget.callService.activeCallNotifier.value != null) {
      return Positioned.fill(child: _buildOverlayContent());
    }
    return const SizedBox.shrink();
  }

  Widget _buildRemoteVideo(ActiveCall call) {
    if (call.type == 'video' && call.status == 'connected') {
      return RepaintBoundary(
        child: ValueListenableBuilder<MediaStream?>(
          valueListenable: widget.callService.remoteStreamNotifier,
          builder: (context, remote, _) {
            if (remote == null || _remoteRenderer == null) return const SizedBox.expand(child: ColoredBox(color: Color(0xFF1A1A1A)));
            return RTCVideoView(
              _remoteRenderer!,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              filterQuality: FilterQuality.medium,
            );
          },
        ),
      );
    }
    // Audio call connected or incoming/dialing/connecting: show avatar
    return RepaintBoundary(child: _buildPlaceholderAvatar(call));
  }

  Widget _buildLocalVideo(ActiveCall call) {
    if (call.type != 'video') return const SizedBox.shrink();
    return Positioned(
      top: 40,
      right: 16,
      width: 120,
      height: 160,
      child: RepaintBoundary(
        child: ValueListenableBuilder<MediaStream?>(
          valueListenable: widget.callService.localStreamNotifier,
          builder: (context, local, _) {
            if (local == null || _localRenderer == null) return const SizedBox.shrink();
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RTCVideoView(
                  _localRenderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true,
                  filterQuality: FilterQuality.low,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholderAvatar(ActiveCall call) {
    final l10n = AppLanguageService.instance;
    final avatarUrl = call.user.avatar;
    final statusText = call.status == 'incoming'
        ? (call.type == 'video' ? l10n.t('call_incoming_video') : l10n.t('call_incoming_audio'))
        : call.status == 'dialing'
            ? '${call.user.name.toUpperCase()} ${l10n.t('call_dialing')}'
            : l10n.t('call_connecting');

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF18181B), // website: bg-zinc-900
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: BondhuTokens.primary.withValues(alpha: 0.3),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 70,
                backgroundColor: BondhuTokens.primary.withValues(alpha: 0.15),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null || avatarUrl.isEmpty 
                    ? Icon(Icons.person, size: 70, color: BondhuTokens.primary.withValues(alpha: 0.8))
                    : null,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              call.user.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: BondhuTokens.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: BondhuTokens.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                statusText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BondhuTokens.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ActiveCall call) {
    if (call.status != 'connected') return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppLanguageService.instance.t('call_live'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => widget.callService.endCallByUser(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionOverlay(ActiveCall call) {
    if (call.status != 'connected') return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: widget.callService.isLiveScriptEnabledNotifier,
      builder: (context, liveOn, _) {
        if (!liveOn) return const SizedBox.shrink();
        return Positioned(
          left: 16,
          right: 16,
          bottom: 180,
          child: RepaintBoundary(
            child: _CaptionStrip(
              remoteName: call.user.name,
              remoteTranscriptNotifier: widget.callService.remoteTranscriptNotifier,
              transcriptNotifier: widget.callService.transcriptNotifier,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(ActiveCall call) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: call.status == 'incoming'
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _callButton(
                      icon: Icons.call_rounded,
                      color: BondhuTokens.primary,
                      onTap: () => widget.callService.acceptCall(),
                      size: 72,
                    ),
                    const SizedBox(width: 40),
                    _callButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.red,
                      onTap: widget.callService.declineCall,
                      size: 72,
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (call.status == 'connected')
                      _toolButton(
                        Icons.closed_caption_rounded,
                        widget.callService.isLiveScriptEnabledNotifier,
                        widget.callService.toggleLiveScript,
                      ),
                    if (call.status == 'connected')
                      _toolButton(
                        Icons.mic_rounded,
                        widget.callService.isAudioMutedNotifier,
                        widget.callService.toggleAudio,
                        muteColor: true,
                      ),
                    if (call.status == 'connected' && call.type == 'video') ...[
                      _toolButton(
                        Icons.videocam_rounded,
                        widget.callService.isVideoMutedNotifier,
                        widget.callService.toggleVideo,
                        muteColor: true,
                      ),
                      // Switch front/back camera during video calls.
                      _simpleToolButton(
                        Icons.cameraswitch_rounded,
                        () => widget.callService.switchCamera(),
                      ),
                    ],
                    if (call.status == 'connected') _minimizeButton(),
                    _callButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.red,
                      size: 64,
                      onTap: () => widget.callService.endCallByUser(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _callButton({required IconData icon, required Color color, double size = 64, required VoidCallback onTap}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
        ),
      ),
    );
  }

  Widget _minimizeButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => widget.callService.setMinimized(true),
          customBorder: const CircleBorder(),
          child: const Center(
            child: Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, ValueNotifier<bool> notifier, VoidCallback onTap, {bool muteColor = false}) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final isMuted = muteColor && value;
        final isActive = value && !muteColor;
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isMuted 
                ? Colors.red.withValues(alpha: 0.9)
                : isActive
                    ? BondhuTokens.primary.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: isMuted
                  ? Colors.red
                  : isActive
                      ? BondhuTokens.primary
                      : Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  icon,
                  color: isMuted
                      ? Colors.white
                      : isActive
                          ? BondhuTokens.primary
                          : Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _simpleToolButton(IconData icon, VoidCallback onTap) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
