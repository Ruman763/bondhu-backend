import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/mood_status_service.dart';
import '../services/supabase_service.dart';
import '../services/privacy_settings_service.dart';
import '../services/profile_theme_service.dart';
import 'my_qr_code_screen.dart';
import 'privacy_policy_sheet.dart';
import 'scan_qr_screen.dart';
import 'audience_profile_screen.dart';
import '../services/block_service.dart';
import '../services/chat_service.dart';
import '../services/chat_vibration_service.dart';
import '../services/message_sync_crypto_service.dart';
import 'chat_migration_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.currentUser,
    required this.isDark,
    required this.onDarkModeChanged,
    required this.onLogout,
    required this.onProfileUpdated,
    this.onBondhuInviteScanned,
  });

  final AuthUser currentUser;
  final bool isDark;
  final ValueChanged<bool> onDarkModeChanged;
  final Future<void> Function() onLogout;
  final ValueChanged<AuthUser> onProfileUpdated;
  /// When user scans a Bondhu invite QR and taps "Start chat". Call with ref (email); caller should open chat.
  final void Function(String ref)? onBondhuInviteScanned;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _locationController;
  String _currentLang = 'en';
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;
  bool _shareReadReceipts = true;
  bool _saving = false;
  bool _messageSyncOn = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.name ?? '');
    _bioController = TextEditingController(text: widget.currentUser.bio ?? '');
    _locationController = TextEditingController(text: widget.currentUser.location ?? '');
    _currentLang = AppLanguageService.instance.current;
    _loadPrivacyPrefs();
    _loadMessageSyncFlag();
    MoodStatusService.instance.load();
    ChatVibrationService.instance.load();
    ProfileThemeService.instance.load();
  }

  Future<void> _loadPrivacyPrefs() async {
    await PrivacySettingsService.instance.load();
    if (!mounted) return;
    setState(() {
      _showOnlineStatus = PrivacySettingsService.instance.showOnlineStatusOn.value;
      _showLastSeen = PrivacySettingsService.instance.lastSeenOn.value;
      _shareReadReceipts = PrivacySettingsService.instance.readReceiptsOn.value;
    });
  }

  Future<void> _loadMessageSyncFlag() async {
    try {
      final v = await ChatService.cloudMessageBackupEnabledFor(widget.currentUser.email);
      if (mounted) setState(() => _messageSyncOn = v);
    } catch (_) {}
  }

  String? get _accountEmail => widget.currentUser.email?.trim().toLowerCase();

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _isDark => widget.isDark;

  Color get _surface => _isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
  Color get _textPrimary => _isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
  Color get _textMuted => _isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      body: SafeArea(
          child: Column(
            children: [
              _buildModernAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Profile
                      _buildProfileCard(),
                      const SizedBox(height: 20),

                      // Account info directly after profile
                      _sectionTitle(AppLanguageService.instance.t('account')),
                      const SizedBox(height: 8),
                      _buildAccountCard(),
                      const SizedBox(height: 20),
                      _buildAudienceProfileButton(),
                      const SizedBox(height: 20),

                      // General (language, dark mode, basic preferences)
                      _sectionTitle(AppLanguageService.instance.t('preferences')),
                      const SizedBox(height: 8),
                      _buildPreferencesCard(),
                      const SizedBox(height: 20),

                      // Wellbeing: quick feelings control
                      _sectionTitle('Wellbeing'),
                      const SizedBox(height: 8),
                      _buildMoodCard(),
                      const SizedBox(height: 20),

                      // Privacy & security
                      _sectionTitle(AppLanguageService.instance.t('privacy_security')),
                      const SizedBox(height: 8),
                      _buildPrivacyPresenceCard(),
                      const SizedBox(height: 12),
                      _buildPrivacyCard(),
                      const SizedBox(height: 12),
                      _sectionTitle(AppLanguageService.instance.t('message_sync_section_title')),
                      const SizedBox(height: 8),
                      _buildMessageSyncCard(),
                      const SizedBox(height: 20),

                      // Actions
                      _buildSaveButton(),
                      const SizedBox(height: 10),
                      _buildSignOutButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }


  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      backgroundColor: _isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _textPrimary),
          style: IconButton.styleFrom(
            backgroundColor: _isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
            padding: const EdgeInsets.all(10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      title: Text(
        AppLanguageService.instance.t('settings'),
        style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: _textPrimary, letterSpacing: -0.3),
      ),
      centerTitle: true,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: BondhuTokens.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _textMuted,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(BondhuTokens.radiusXl),
        border: Border.all(
          color: _isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
          width: 1,
        ),
        boxShadow: _isDark
            ? BondhuTokens.cardShadowDark
            : [
                ...BondhuTokens.cardShadowLight,
                BoxShadow(color: BondhuTokens.primary.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4)),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BondhuTokens.radiusXl),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildProfileCard() {
    return _card(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isDark
                  ? [BondhuTokens.primary.withValues(alpha: 0.08), BondhuTokens.primary.withValues(alpha: 0.02)]
                  : [BondhuTokens.primary.withValues(alpha: 0.06), BondhuTokens.primary.withValues(alpha: 0.02)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(BondhuTokens.radiusXl)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [BondhuTokens.primary, BondhuTokens.primaryLight],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BondhuTokens.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
                      image: widget.currentUser.avatar != null && widget.currentUser.avatar!.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(widget.currentUser.avatar!, scale: 1.0),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: (widget.currentUser.avatar == null || widget.currentUser.avatar!.isEmpty)
                        ? Icon(Icons.person_rounded, size: 28, color: _textMuted)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.currentUser.name ?? AppLanguageService.instance.t('user'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.currentUser.email ?? '',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.camera_alt_rounded, size: 12, color: BondhuTokens.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Tap to change photo',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: BondhuTokens.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _profileQrChip(
                    icon: Icons.qr_code_2_rounded,
                    tooltip: 'My QR Code',
                    onTap: _openMyQrCode,
                  ),
                  const SizedBox(width: 8),
                  _profileQrChip(
                    icon: Icons.qr_code_scanner_rounded,
                    tooltip: 'Scan QR Code',
                    onTap: _openScanQr,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileQrChip({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BondhuTokens.primary.withValues(alpha: _isDark ? 0.14 : 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: BondhuTokens.primary.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, size: 22, color: BondhuTokens.primary),
          ),
        ),
      ),
    );
  }

  void _openMyQrCode() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyQrCodeScreen(
          userName: widget.currentUser.name ?? 'User',
          userEmail: widget.currentUser.email,
          avatarUrl: widget.currentUser.avatar,
          isDark: _isDark,
        ),
      ),
    );
  }

  void _openScanQr() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanQrScreen(
          isDark: _isDark,
          onBondhuInviteScanned: widget.onBondhuInviteScanned != null
              ? (ref) {
                  Navigator.of(context).pop();
                  widget.onBondhuInviteScanned!(ref);
                }
              : null,
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    final ext = x.path.split('.').last;
    final url = await uploadFileFromBytes(bytes, 'avatar.$ext');
    if (url == null || !mounted) return;
    final profile = await syncProfile(widget.currentUser);
    if (profile == null || !mounted) return;
    await updateProfile(profile.docId, {'avatar': url});
    final u = widget.currentUser;
    final updated = AuthUser(
      email: u.email,
      name: u.name,
      avatar: url,
      docId: profile.docId,
      bio: u.bio,
      location: u.location,
      followers: u.followers,
      following: u.following,
    );
    await storeUser(updated);
    widget.onProfileUpdated(updated);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguageService.instance.t('photo_selected')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _buildPreferencesCard() {
    return _card(
      children: [
        _settingRow(AppLanguageService.instance.t('language'), _langChips()),
        _divider(),
        _settingRow(AppLanguageService.instance.t('dark_mode'), _toggle(widget.isDark, widget.onDarkModeChanged)),
        _divider(),
        _settingRow(
          AppLanguageService.instance.t('show_online_status'),
          _toggle(_showOnlineStatus, (v) async {
            setState(() => _showOnlineStatus = v);
            await PrivacySettingsService.instance.setShowOnlineStatus(v);
          }),
        ),
        _divider(),
        _settingRow(
          AppLanguageService.instance.t('show_last_seen'),
          _toggle(_showLastSeen, (v) async {
            setState(() => _showLastSeen = v);
            await PrivacySettingsService.instance.setLastSeen(v);
          }),
        ),
        _divider(),
        _settingRow(
          AppLanguageService.instance.t('share_read_receipts'),
          _toggle(_shareReadReceipts, (v) async {
            setState(() => _shareReadReceipts = v);
            await PrivacySettingsService.instance.setReadReceipts(v);
          }),
        ),
      ],
    );
  }

  Widget _settingRow(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: _textPrimary)),
          trailing,
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(height: 1, thickness: 1, indent: 20, endIndent: 20, color: _isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight);
  }

  Widget _buildMessageSyncCard() {
    final t = AppLanguageService.instance.t;
    return _card(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BondhuTokens.primary.withValues(alpha: _isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.cloud_sync_rounded, size: 22, color: BondhuTokens.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('message_sync_title'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('message_sync_sub'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _messageSyncOn ? t('message_sync_switch_on_label') : t('message_sync_switch_off_label'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ),
              Switch(
                value: _messageSyncOn,
                onChanged: _saving ? null : _onMessageSyncToggled,
                activeThumbColor: BondhuTokens.primary,
              ),
            ],
          ),
        ),
        _divider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(Icons.phonelink_setup_rounded, color: BondhuTokens.primary),
          title: Text(
            t('migration_title'),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary),
          ),
          subtitle: Text(
            t('migration_settings_sub'),
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted, height: 1.35),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: _textMuted, size: 22),
          onTap: _saving
              ? null
              : () async {
                  final email = widget.currentUser.email?.trim() ?? '';
                  if (email.isEmpty) return;
                  final imported = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ChatMigrationScreen(
                        accountEmail: email,
                        isDark: _isDark,
                      ),
                    ),
                  );
                  if (imported == true) {
                    try {
                      await ChatService.active?.recoverAfterMigration();
                    } catch (_) {}
                  }
                },
        ),
      ],
    );
  }

  Future<void> _onMessageSyncToggled(bool wantOn) async {
    HapticFeedback.selectionClick();
    if (wantOn == _messageSyncOn) return;
    if (!wantOn) {
      final ok = await _confirmTurnOffMessageSync();
      if (!ok || !mounted) return;
      setState(() => _messageSyncOn = false);
      await ChatService.setCloudMessageBackupFor(_accountEmail, false);
      return;
    }
    setState(() => _messageSyncOn = true);
    await ChatService.setCloudMessageBackupFor(_accountEmail, true);
  }

  Future<bool> _confirmTurnOffMessageSync() async {
    final lang = AppLanguageService.instance;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          lang.t('message_sync_off_title'),
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: Text(
          lang.t('message_sync_off_body'),
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(lang.t('cancel'), style: GoogleFonts.plusJakartaSans(color: _textMuted, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: BondhuTokens.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              lang.t('message_sync_turn_off_confirm'),
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return go == true;
  }

  Widget _buildMoodCard() {
    return _card(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(
            'Feeling',
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary),
          ),
          subtitle: ValueListenableBuilder<String>(
            valueListenable: MoodStatusService.instance.currentMoodKey,
            builder: (context, key, child) {
              final opt = MoodStatusService.options.firstWhere(
                (o) => o.key == key,
                orElse: () => MoodStatusService.options.first,
              );
              final label = opt.label.isEmpty ? 'Not set' : opt.label;
              final emoji = opt.emoji;
              return Text(
                emoji.isNotEmpty ? '$emoji  $label' : label,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted),
              );
            },
          ),
          trailing: TextButton(
            onPressed: _showMoodBottomSheet,
            child: Text(
              'Change',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: BondhuTokens.primary),
            ),
          ),
        ),
      ],
    );
  }

  void _showMoodBottomSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final surface = _isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How are you feeling?',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: MoodStatusService.instance.currentMoodKey,
                  builder: (context, key, child) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: MoodStatusService.options.map((opt) {
                        final selected = key == opt.key;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              MoodStatusService.instance.setMood(opt.key);
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? BondhuTokens.primary.withValues(alpha: 0.2) : (_isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.inputBgLight),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? BondhuTokens.primary : Colors.transparent,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (opt.emoji.isNotEmpty) ...[
                                    Text(opt.emoji, style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    opt.label.isEmpty ? 'None' : opt.label,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      color: selected ? BondhuTokens.primary : _textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrivacyPresenceCard() {
    return _card(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: PrivacySettingsService.instance.readReceiptsOn,
          builder: (context, on, child) => _switchTile('Read receipts', 'Let others see when you read messages', on, (v) => PrivacySettingsService.instance.setReadReceipts(v)),
        ),
        _divider(),
        ValueListenableBuilder<bool>(
          valueListenable: PrivacySettingsService.instance.lastSeenOn,
          builder: (context, on, child) => _switchTile('Last seen', 'Show when you were last active', on, (v) => PrivacySettingsService.instance.setLastSeen(v)),
        ),
        _divider(),
        ValueListenableBuilder<bool>(
          valueListenable: PrivacySettingsService.instance.typingIndicatorOn,
          builder: (context, on, child) => _switchTile('Typing indicator', 'Show "typing…" when you\'re writing', on, (v) => PrivacySettingsService.instance.setTypingIndicator(v)),
        ),
      ],
    );
  }

  Widget _switchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
      subtitle: Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted)),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: BondhuTokens.primary),
    );
  }

  // Focus mode and usage summary removed from visible settings to keep things simple.

  Widget _langChips() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.inputBgLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _langChip('English', 'en'),
          _langChip('বাংলা', 'bn'),
        ],
      ),
    );
  }

  Widget _langChip(String label, String value) {
    final selected = _currentLang == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await AppLanguageService.instance.setLanguage(value);
          if (mounted) setState(() => _currentLang = value);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [BondhuTokens.primaryDark, BondhuTokens.primary],
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected ? [BoxShadow(color: BondhuTokens.primary.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black : _textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 28,
        decoration: BoxDecoration(
          gradient: value
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [BondhuTokens.primaryDark, BondhuTokens.primary],
                )
              : null,
          color: value ? null : (_isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.textMutedLight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: value
              ? [
                  BoxShadow(color: BondhuTokens.primary.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2)),
                ]
              : null,
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 22,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    final t = AppLanguageService.instance.t;
    return _card(
      children: [
        _accountCompactField(
          label: t('full_name'),
          controller: _nameController,
          icon: Icons.badge_outlined,
        ),
        _divider(),
        _accountCompactEmailRow(
          label: t('email_address'),
          value: widget.currentUser.email ?? '',
        ),
        _divider(),
        _accountCompactBioField(
          label: t('about_me'),
          controller: _bioController,
          icon: Icons.short_text_rounded,
        ),
        _divider(),
        _accountCompactField(
          label: t('location'),
          controller: _locationController,
          icon: Icons.location_on_outlined,
        ),
      ],
    );
  }

  /// One button to open the dedicated "Profile by audience" screen.
  Widget _buildAudienceProfileButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final updated = await Navigator.of(context).push<AuthUser>(
            MaterialPageRoute<AuthUser>(
              builder: (context) => AudienceProfileScreen(
                currentUser: widget.currentUser,
                isDark: _isDark,
                onProfileUpdated: widget.onProfileUpdated,
              ),
            ),
          );
          if (updated != null && mounted) widget.onProfileUpdated(updated);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BondhuTokens.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.person_pin_rounded, size: 26, color: BondhuTokens.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguageService.instance.t('profile_by_audience'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLanguageService.instance.t('profile_by_audience_hint'),
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Borderless fields so Account rows sit flush on the card (no boxed outline).
  InputDecoration _accountInputDecoration() {
    return const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );
  }

  /// Dense account row: small leading icon, floating-style label inside field.
  Widget _accountCompactField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: BondhuTokens.primary.withValues(alpha: 0.9)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.25, color: _textPrimary),
              decoration: _accountInputDecoration().copyWith(
                labelText: label,
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCompactBioField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(icon, size: 20, color: BondhuTokens.primary.withValues(alpha: 0.9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 2,
              maxLines: 3,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.35, color: _textPrimary),
              decoration: _accountInputDecoration().copyWith(
                labelText: label,
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                alignLabelWithHint: true,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCompactEmailRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.mail_outline_rounded, size: 20, color: _textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _textMuted,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.lock_outline_rounded, size: 12, color: _textMuted),
                  ],
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value.isEmpty ? '—' : value,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyCard() {
    return _card(
      children: [
        _privacyTile(Icons.shield_outlined, AppLanguageService.instance.t('privacy_policy'), () => showBondhuPrivacyPolicy(context, _isDark)),
        _divider(),
        _privacyTile(Icons.block_rounded, 'Block list', _showBlockList),
        _divider(),
        _privacyTile(Icons.lock_rounded, AppLanguageService.instance.t('change_password'), _showChangePassword),
      ],
    );
  }

  Widget _privacyTile(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isDark
                        ? [BondhuTokens.primary.withValues(alpha: 0.2), BondhuTokens.primary.withValues(alpha: 0.08)]
                        : [BondhuTokens.primary.withValues(alpha: 0.15), BondhuTokens.primary.withValues(alpha: 0.06)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: BondhuTokens.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockList() {
    final surface = _surface;
    final textPrimary = _textPrimary;
    final textMuted = _textMuted;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    Text(
                      'Block list',
                      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(Icons.close_rounded, color: textMuted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: BlockService.instance.blockedIdsNotifier,
                  builder: (context, list, child) {
                    if (list.isEmpty) {
                      return Center(
                        child: Text(
                          'No blocked users',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textMuted),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final id = list[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          title: Text(
                            id,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: () async => await BlockService.instance.remove(id),
                            child: Text(AppLanguageService.instance.t('unblock'),
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: BondhuTokens.primary, fontWeight: FontWeight.w600)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePassword() {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final cardBg = _surface;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          AppLanguageService.instance.t('change_password'),
          style: GoogleFonts.plusJakartaSans(color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppLanguageService.instance.t('current_password'), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: oldController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: AppLanguageService.instance.t('enter_current_password'),
                  hintStyle: TextStyle(color: _textMuted),
                  filled: true,
                  fillColor: _isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.plusJakartaSans(color: _textPrimary),
              ),
              const SizedBox(height: 16),
              Text(AppLanguageService.instance.t('new_password'), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: newController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: AppLanguageService.instance.t('enter_new_password_hint'),
                  hintStyle: TextStyle(color: _textMuted),
                  filled: true,
                  fillColor: _isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.plusJakartaSans(color: _textPrimary),
              ),
              const SizedBox(height: 16),
              Text(AppLanguageService.instance.t('confirm_new_password'), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: AppLanguageService.instance.t('confirm_new_password_hint'),
                  hintStyle: TextStyle(color: _textMuted),
                  filled: true,
                  fillColor: _isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.plusJakartaSans(color: _textPrimary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguageService.instance.t('cancel'), style: GoogleFonts.plusJakartaSans(color: _textMuted, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () async {
              final oldPass = oldController.text;
              final newPass = newController.text;
              final confirm = confirmController.text;
              if (oldPass.isEmpty || newPass.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLanguageService.instance.t('please_fill_all_fields')), behavior: SnackBarBehavior.floating),
                );
                return;
              }
              if (newPass.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLanguageService.instance.t('password_min_length')), behavior: SnackBarBehavior.floating),
                );
                return;
              }
              if (newPass != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLanguageService.instance.t('new_passwords_do_not_match')), behavior: SnackBarBehavior.floating),
                );
                return;
              }
              try {
                await updatePassword(oldPassword: oldPass, newPassword: newPass);
                final email = widget.currentUser.email?.trim().toLowerCase();
                if (email != null && email.isNotEmpty) {
                  try {
                    final prof = await syncProfile(widget.currentUser);
                    if (prof != null) {
                      await MessageSyncCryptoService.instance.cacheKeyFromPassword(
                        email: email,
                        password: newPass,
                        messageCryptoSaltB64: prof.messageCryptoSalt,
                      );
                    }
                  } catch (_) {}
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLanguageService.instance.t('password_updated_successfully')), behavior: SnackBarBehavior.floating, backgroundColor: BondhuTokens.primary),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().contains('user_invalid_credentials')
                          ? AppLanguageService.instance.t('current_password_incorrect')
                          : AppLanguageService.instance.t('failed_update_password')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: BondhuTokens.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(AppLanguageService.instance.t('update'), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final profile = await syncProfile(widget.currentUser);
      if (profile == null || !mounted) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      final name = _nameController.text.trim();
      final bio = _bioController.text.trim();
      final location = _locationController.text.trim();
      final payload = <String, dynamic>{
        'name': name.isEmpty ? (widget.currentUser.email ?? '').split('@').first : name,
      };
      if (bio.isNotEmpty) payload['bio'] = bio;
      if (location.isNotEmpty) payload['location'] = location;
      await updateProfile(profile.docId, payload);
      final updated = AuthUser(
        email: widget.currentUser.email,
        name: name.isEmpty ? widget.currentUser.name : name,
        avatar: widget.currentUser.avatar,
        docId: profile.docId,
        bio: bio.isEmpty ? null : bio,
        location: location.isEmpty ? null : location,
        followers: widget.currentUser.followers,
        following: widget.currentUser.following,
      );
      await storeUser(updated);
      if (mounted) {
        widget.onProfileUpdated(updated);
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('profile_saved')), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('failed_save_try_again')), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Widget _buildSaveButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BondhuTokens.primaryDark, BondhuTokens.primary],
        ),
        boxShadow: [
          BoxShadow(color: BondhuTokens.primary.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _saving ? null : _saveProfile,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Text(
              _saving ? AppLanguageService.instance.t('saving') : AppLanguageService.instance.t('save_changes'),
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(context).pop();
          await widget.onLogout();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.inputBgLight,
            border: Border.all(color: _isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, size: 20, color: Colors.red.shade400),
              const SizedBox(width: 10),
              Text(
                AppLanguageService.instance.t('sign_out'),
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.red.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
