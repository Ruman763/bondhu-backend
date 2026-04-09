import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/call_service.dart';

/// Overlay that plays the callee's custom voice or video message when the call was declined.
/// Shown to the caller after call_declined is received with voiceMessageUrl or videoMessageUrl.
class CustomCallMessageOverlay extends StatefulWidget {
  const CustomCallMessageOverlay({
    super.key,
    required this.callService,
    required this.isDark,
  });

  final CallService callService;
  final bool isDark;

  @override
  State<CustomCallMessageOverlay> createState() => _CustomCallMessageOverlayState();
}

class _CustomCallMessageOverlayState extends State<CustomCallMessageOverlay> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    widget.callService.customMessageToPlayNotifier.addListener(_onMessageToPlayChanged);
    _onMessageToPlayChanged();
  }

  @override
  void dispose() {
    widget.callService.customMessageToPlayNotifier.removeListener(_onMessageToPlayChanged);
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _onMessageToPlayChanged() {
    final msg = widget.callService.customMessageToPlayNotifier.value;
    if (msg == null || !msg.hasMessage) {
      _entry?.remove();
      _entry = null;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = Navigator.of(context, rootNavigator: true).overlay;
      if (overlay == null) return;
      _entry?.remove();
      _entry = OverlayEntry(
        builder: (context) => _CustomMessagePlaybackDialog(
          playback: msg,
          isDark: widget.isDark,
          onClose: () {
            widget.callService.customMessageToPlayNotifier.value = null;
            _entry?.remove();
            _entry = null;
          },
        ),
      );
      overlay.insert(_entry!);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _CustomMessagePlaybackDialog extends StatefulWidget {
  const _CustomMessagePlaybackDialog({
    required this.playback,
    required this.isDark,
    required this.onClose,
  });

  final CustomCallMessagePlayback playback;
  final bool isDark;
  final VoidCallback onClose;

  @override
  State<_CustomMessagePlaybackDialog> createState() => _CustomMessagePlaybackDialogState();
}

class _CustomMessagePlaybackDialogState extends State<_CustomMessagePlaybackDialog> {
  AudioPlayer? _audioPlayer;
  VideoPlayerController? _videoController;
  bool _playing = false;
  bool _error = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startPlayback();
  }

  Future<void> _startPlayback() async {
    final url = widget.playback.urlToPlay;
    if (url == null || url.isEmpty) {
      widget.onClose();
      return;
    }
    if (widget.playback.callType == 'video' && widget.playback.videoMessageUrl != null) {
      try {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
        await _videoController!.initialize();
        if (!mounted) return;
        _videoController!.addListener(_videoListener);
        setState(() {});
        await _videoController!.play();
        if (mounted) {
          setState(() => _playing = true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = true;
            _errorMessage = e.toString();
          });
        }
      }
    } else {
      try {
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.play(UrlSource(url));
        if (mounted) {
          setState(() => _playing = true);
        }
        _audioPlayer!.onPlayerComplete.listen((_) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
          }
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = true;
            _errorMessage = e.toString();
          });
        }
      }
    }
  }

  void _videoListener() {
    if (_videoController != null && _videoController!.value.isCompleted && mounted) {
      widget.onClose();
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _videoController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLanguageService.instance;
    final isVideo = widget.playback.callType == 'video';
    final title = isVideo
        ? l10n.t('custom_call_message_video_title').replaceAll('%s', widget.playback.calleeName)
        : l10n.t('custom_call_message_voice_title').replaceAll('%s', widget.playback.calleeName);

    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage ?? l10n.t('something_went_wrong'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            else if (isVideo && _videoController != null && _videoController!.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              )
            else if (!isVideo)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.record_voice_over_rounded,
                      size: 80,
                      color: BondhuTokens.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(height: 24),
                    if (_playing)
                      Text(
                        l10n.t('custom_call_message_playing'),
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Colors.white70),
                      )
                    else
                      const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: BondhuTokens.primary)),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: widget.onClose,
                    tooltip: l10n.t('close'),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: ElevatedButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.done_rounded, size: 20),
                label: Text(l10n.t('done'), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BondhuTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
