import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../design_tokens.dart';
import '../services/invite_service.dart';
import '../services/profile_theme_service.dart';

/// WeChat-style "My QR Code" screen: avatar, name, subtitle, large QR, Save image & Share.
class MyQrCodeScreen extends StatefulWidget {
  const MyQrCodeScreen({
    super.key,
    required this.userName,
    required this.userEmail,
    this.avatarUrl,
    required this.isDark,
  });

  final String userName;
  final String? userEmail;
  final String? avatarUrl;
  final bool isDark;

  @override
  State<MyQrCodeScreen> createState() => _MyQrCodeScreenState();
}

class _MyQrCodeScreenState extends State<MyQrCodeScreen> {
  final GlobalKey _qrCardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final payload = InviteService.instance.getQrPayload(referralId: widget.userEmail);
    final surface = isDark ? const Color(0xFF0F0F0F) : BondhuTokens.bgLight;
    final cardBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);
    return ValueListenableBuilder<Color>(
      valueListenable: ProfileThemeService.instance.accentColor,
      builder: (context, accent, _) => _buildBody(accent, payload, surface, cardBg, textPrimary, textMuted, isDark),
    );
  }

  Widget _buildBody(Color accent, String payload, Color surface, Color cardBg, Color textPrimary, Color textMuted, bool isDark) {
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textPrimary),
        ),
        title: Text(
          'My QR Code',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            RepaintBoundary(
              key: _qrCardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: accent.withValues(alpha: 0.15),
                      backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                          ? NetworkImage(widget.avatarUrl!)
                          : null,
                      child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                          ? Text(
                              (widget.userName.isNotEmpty ? widget.userName[0] : '?').toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.userName.isEmpty ? 'Bondhu User' : widget.userName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Scan to add me on Bondhu',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF111113),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF111113),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _saveOrShareImage(context, share: false),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text('Save image'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _saveOrShareImage(context, share: true),
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('Share'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveOrShareImage(BuildContext context, {required bool share}) async {
    try {
      final boundary = _qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) _showSnack('Could not capture image');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/bondhu_my_qr.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.offsetInBytes + byteData.lengthInBytes));
      if (share) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Add me on Bondhu! Scan my QR code or use the link.',
        );
      } else {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'My Bondhu QR Code — save this image to your photos.',
        );
      }
      if (mounted) _showSnack(share ? 'Share sheet opened' : 'Save via share (e.g. Save Image)');
    } catch (e) {
      if (mounted) _showSnack('Failed: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
