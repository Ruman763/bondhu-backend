import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/chat_migration_service.dart';
import '../services/chat_service.dart';

/// WeChat-style Scan QR screen: camera scanner, handle Bondhu invite links and other URLs.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({
    super.key,
    required this.isDark,
    this.onBondhuInviteScanned,
  });

  final bool isDark;
  /// When a Bondhu invite link is scanned (ref = email/id), call with the ref. Can navigate to add contact or start chat.
  final void Function(String ref)? onBondhuInviteScanned;

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _hasScanned = false;
  bool _linking = false;
  String? _linkingStatusKey;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final list = capture.barcodes;
    if (list.isEmpty) return;
    final barcode = list.first;
    final raw = barcode.rawValue;
    if (raw == null || raw.isEmpty) return;
    _hasScanned = true;
    HapticFeedback.mediumImpact();
    _handlePayload(raw.trim());
  }

  void _handlePayload(String payload) {
    // Device link QR (JSON): {"k":"bondhu-link","i":"...","t":"..."}
    if (payload.startsWith('{')) {
      try {
        final m = jsonDecode(payload) as Map<String, dynamic>;
        final kind = (m['k']?.toString() ?? '').trim();
        if (kind == 'bondhu-link') {
          final sid = (m['i']?.toString() ?? '').trim();
          final sec = (m['t']?.toString() ?? '').trim();
          if (sid.isNotEmpty && sec.isNotEmpty) {
            _handleDeviceLink(sid, sec);
            return;
          }
        }
      } catch (_) {}
    }
    // Device link QR: bondhu-link://v1?sid=...&sec=...
    if (payload.startsWith('bondhu-link://')) {
      try {
        final uri = Uri.parse(payload);
        final sid = uri.queryParameters['sid'];
        final sec = uri.queryParameters['sec'];
        if (sid != null && sid.isNotEmpty && sec != null && sec.isNotEmpty) {
          _handleDeviceLink(sid, sec);
          return;
        }
      } catch (_) {}
    }
    // Bondhu invite: https://bondhu.app/invite?ref=...
    if (payload.contains('bondhu.app/invite')) {
      try {
        final uri = Uri.parse(payload);
        final ref = uri.queryParameters['ref'];
        if (ref != null && ref.isNotEmpty) {
          widget.onBondhuInviteScanned?.call(ref);
          if (mounted) _showResultSheet(isBondhu: true, ref: ref);
          return;
        }
      } catch (_) {}
    }
    // Any URL
    if (payload.startsWith('http://') || payload.startsWith('https://')) {
      if (mounted) _showResultSheet(isBondhu: false, url: payload);
      return;
    }
    // Plain text (e.g. other QR content)
    if (mounted) _showResultSheet(isBondhu: false, plainText: payload);
  }

  Future<void> _handleDeviceLink(String sessionId, String secret) async {
    setState(() {
      _linking = true;
      _linkingStatusKey = 'migration_status_transferring';
    });
    final me = await getStoredUser();
    final email = (me?.email ?? '').trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('migration_wrong_account')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _hasScanned = false);
      setState(() {
        _linking = false;
        _linkingStatusKey = null;
      });
      return;
    }
    final qrRaw = '{"k":"bondhu-link","i":"$sessionId","t":"$secret"}';
    final code = await ChatMigrationService.instance.fulfillWebLinkFromPhone(email, qrRaw);
    if (!mounted) return;
    if (code == null) {
      setState(() => _linkingStatusKey = 'migration_status_recovering');
      await ChatService.active?.recoverAfterMigration();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('migration_success')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BondhuTokens.primary,
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLanguageService.instance.t(code)),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() => _hasScanned = false);
    setState(() {
      _linking = false;
      _linkingStatusKey = null;
    });
  }

  void _showResultSheet({bool isBondhu = false, String? ref, String? url, String? plainText}) {
    final isDark = widget.isDark;
    final surface = isDark ? const Color(0xFF18181B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isBondhu && ref != null) ...[
                Icon(Icons.person_add_rounded, size: 48, color: BondhuTokens.primary),
                const SizedBox(height: 12),
                Text(
                  'Bondhu user',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  ref.length > 40 ? '${ref.substring(0, 40)}…' : ref,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onBondhuInviteScanned?.call(ref);
                  },
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  label: const Text('Start chat'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BondhuTokens.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ] else if (url != null) ...[
                Icon(Icons.link_rounded, size: 48, color: BondhuTokens.primary),
                const SizedBox(height: 12),
                Text(
                  'Link detected',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  url.length > 50 ? '${url.substring(0, 50)}…' : url,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: textMuted),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied'), behavior: SnackBarBehavior.floating),
                          );
                        },
                        child: const Text('Copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final uri = Uri.tryParse(url);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ] else if (plainText != null) ...[
                Text(
                  'Content',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  plainText.length > 80 ? '${plainText.substring(0, 80)}…' : plainText,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: plainText));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied'), behavior: SnackBarBehavior.floating),
                    );
                  },
                  child: const Text('Copy'),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _hasScanned = false);
                  Navigator.pop(ctx);
                },
                child: Text('Scan again', style: GoogleFonts.plusJakartaSans(color: textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? const Color(0xFF0F0F0F) : BondhuTokens.bgLight;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded, color: textPrimary),
        ),
        title: Text(
          'Scan QR Code',
          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scan frame overlay (WeChat-style)
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: CustomPaint(
                painter: _CornerAccentPainter(color: BondhuTokens.primary),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_linking && _linkingStatusKey != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLanguageService.instance.t(_linkingStatusKey!),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'Align QR code within the frame',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerAccentPainter extends CustomPainter {
  _CornerAccentPainter({required this.color});

  final Color color;
  static const double _cornerLen = 24;
  static const double _stroke = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, _cornerLen)
        ..lineTo(0, 0)
        ..lineTo(_cornerLen, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - _cornerLen, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, _cornerLen),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height - _cornerLen)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width - _cornerLen, size.height),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(_cornerLen, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, size.height - _cornerLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
