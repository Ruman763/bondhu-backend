import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/chat_migration_service.dart';

/// WeChat-style: move **message decryption keys** from old phone to new phone.
/// Profile/feed/etc. still sync via the account as usual.
class ChatMigrationScreen extends StatefulWidget {
  const ChatMigrationScreen({
    super.key,
    required this.accountEmail,
    required this.isDark,
  });

  final String accountEmail;
  final bool isDark;

  @override
  State<ChatMigrationScreen> createState() => _ChatMigrationScreenState();
}

class _ChatMigrationScreenState extends State<ChatMigrationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _exportLoading = false;
  ChatMigrationQrData? _qrData;
  String? _exportError;

  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _importBusy = false;
  bool _scanHandled = false;
  bool _webBusy = false;
  WebLinkQrData? _webQr;
  String? _webError;
  String? _webStatusKey;

  Color get _surface => widget.isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
  Color get _textPrimary => widget.isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
  Color get _textMuted => widget.isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _createQr() async {
    final lang = AppLanguageService.instance;
    setState(() {
      _exportLoading = true;
      _exportError = null;
      _qrData = null;
    });
    try {
      final data = await ChatMigrationService.instance.prepareExport(widget.accountEmail);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _exportLoading = false;
          _exportError = lang.t('migration_export_failed');
        });
        return;
      }
      setState(() {
        _exportLoading = false;
        _qrData = data;
      });
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (mounted) {
        setState(() {
          _exportLoading = false;
          _exportError = lang.t('migration_export_failed');
        });
      }
    }
  }

  Future<void> _onScan(String raw) async {
    if (_importBusy || _scanHandled) return;
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return;
    setState(() {
      _importBusy = true;
      _scanHandled = true;
    });
    HapticFeedback.mediumImpact();
    final lang = AppLanguageService.instance;
    final code = await ChatMigrationService.instance.applyImport(widget.accountEmail, trimmed);
    if (!mounted) return;
    setState(() => _importBusy = false);
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('migration_success')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BondhuTokens.primary,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _scanHandled = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.t(code)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createWebQrAndWait() async {
    final lang = AppLanguageService.instance;
    setState(() {
      _webBusy = true;
      _webError = null;
      _webQr = null;
      _webStatusKey = 'migration_status_creating_qr';
    });
    final data = await ChatMigrationService.instance.prepareWebLinkRequest(widget.accountEmail);
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _webBusy = false;
        _webError = lang.t('migration_export_failed');
        _webStatusKey = null;
      });
      return;
    }
    setState(() {
      _webQr = data;
      _webStatusKey = 'migration_status_waiting_phone';
    });
    final code = await ChatMigrationService.instance.waitAndApplyWebLink(
      accountEmail: widget.accountEmail,
      documentId: data.documentId,
      tokenBase64Url: data.tokenBase64Url,
    );
    if (!mounted) return;
    setState(() {
      _webBusy = false;
      _webStatusKey = null;
    });
    if (code == null) {
      setState(() => _webStatusKey = 'migration_status_recovered');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('migration_success')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: BondhuTokens.primary,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _webError = lang.t(code);
      _webStatusKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppLanguageService.instance;
    return Scaffold(
      backgroundColor: widget.isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      appBar: AppBar(
        backgroundColor: widget.isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
        elevation: 0,
        title: Text(
          lang.t('migration_title'),
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        iconTheme: IconThemeData(color: _textPrimary),
        bottom: TabBar(
          controller: _tabController,
          labelColor: BondhuTokens.primary,
          unselectedLabelColor: _textMuted,
          indicatorColor: BondhuTokens.primary,
          tabs: [
            Tab(text: lang.t('migration_old_phone')),
            Tab(text: lang.t('migration_new_phone')),
            Tab(text: lang.t('migration_web_tab')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOldPhoneTab(lang),
          _buildNewPhoneTab(lang),
          _buildWebTab(lang),
        ],
      ),
    );
  }

  Widget _buildOldPhoneTab(AppLanguageService lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lang.t('migration_old_body'),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted, height: 1.45),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _exportLoading ? null : _createQr,
            style: FilledButton.styleFrom(
              backgroundColor: BondhuTokens.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _exportLoading
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(lang.t('migration_create_qr'), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
          if (_exportError != null) ...[
            const SizedBox(height: 12),
            Text(_exportError!, style: GoogleFonts.plusJakartaSans(color: Colors.red.shade400, fontSize: 13)),
          ],
          if (_qrData != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
              ),
              child: Column(
                children: [
                  Text(
                    lang.t('migration_scan_hint'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  QrImageView(
                    data: _qrData!.qrPayload,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNewPhoneTab(AppLanguageService lang) {
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            lang.t('migration_web_scan_unavailable'),
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted, height: 1.45),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            lang.t('migration_new_body'),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted, height: 1.45),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scanner,
                onDetect: (capture) {
                  if (_importBusy) return;
                  final b = capture.barcodes;
                  if (b.isEmpty) return;
                  final raw = b.first.rawValue;
                  if (raw == null || raw.isEmpty) return;
                  _onScan(raw);
                },
              ),
              if (_importBusy)
                Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebTab(AppLanguageService lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lang.t('migration_web_body'),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted, height: 1.45),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _webBusy ? null : _createWebQrAndWait,
            style: FilledButton.styleFrom(
              backgroundColor: BondhuTokens.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _webBusy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(lang.t('migration_web_create_qr'), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
          if (_webError != null) ...[
            const SizedBox(height: 12),
            Text(_webError!, style: GoogleFonts.plusJakartaSans(color: Colors.red.shade400, fontSize: 13)),
          ],
          if (_webStatusKey != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: BondhuTokens.primary.withValues(alpha: widget.isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BondhuTokens.primary.withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lang.t(_webStatusKey!),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_webQr != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
              ),
              child: Column(
                children: [
                  Text(
                    lang.t('migration_web_scan_hint'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  QrImageView(
                    data: _webQr!.qrPayload,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
