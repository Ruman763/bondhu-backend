import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';

/// Dedicated modern screen to set up profile by audience: Default, Personal, Professional.
/// User can set different name, bio, and picture per profile and see who sees which.
class AudienceProfileScreen extends StatefulWidget {
  const AudienceProfileScreen({
    super.key,
    required this.currentUser,
    required this.isDark,
    required this.onProfileUpdated,
  });

  final AuthUser currentUser;
  final bool isDark;
  final ValueChanged<AuthUser> onProfileUpdated;

  @override
  State<AudienceProfileScreen> createState() => _AudienceProfileScreenState();
}

/// Accent color per audience for a more distinct, persona-based feel.
Color _accentForAudience(int index, bool isDark) {
  switch (index) {
    case 0:
      return BondhuTokens.primary; // Default: teal
    case 1:
      return const Color(0xFFE11D48); // Personal: rose
    case 2:
      return const Color(0xFF6366F1); // Professional: indigo
    default:
      return BondhuTokens.primary;
  }
}

class _AudienceProfileScreenState extends State<AudienceProfileScreen> {
  ProfileDoc? _profile;
  bool _loading = true;
  bool _saving = false;
  int _selectedAudienceIndex = 0; // 0 Default, 1 Personal, 2 Professional

  final _defaultName = TextEditingController();
  final _defaultBio = TextEditingController();
  final _personalName = TextEditingController();
  final _personalBio = TextEditingController();
  final _professionalName = TextEditingController();
  final _professionalBio = TextEditingController();

  String? _defaultAvatarUrl;
  String? _personalAvatarUrl;
  String? _professionalAvatarUrl;

  @override
  void initState() {
    super.initState();
    _defaultName.text = widget.currentUser.name ?? '';
    _defaultBio.text = widget.currentUser.bio ?? '';
    _defaultAvatarUrl = widget.currentUser.avatar;
    _loadProfile();
  }

  @override
  void dispose() {
    _defaultName.dispose();
    _defaultBio.dispose();
    _personalName.dispose();
    _personalBio.dispose();
    _professionalName.dispose();
    _professionalBio.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    ProfileDoc? profile;
    try {
      profile = await syncProfile(widget.currentUser).timeout(
        const Duration(seconds: 18),
      );
    } catch (_) {
      profile = null;
    }
    if (profile == null) {
      final email = (widget.currentUser.email ?? '').trim().toLowerCase();
      if (email.isNotEmpty) {
        try {
          profile = await getProfileByUserId(email).timeout(const Duration(seconds: 8));
        } catch (_) {
          profile = null;
        }
      }
    }
    if (profile == null) {
      // Last-resort local fallback so this screen remains usable even when
      // profile sync/read is temporarily blocked on web.
      final email = (widget.currentUser.email ?? '').trim().toLowerCase();
      profile = ProfileDoc(
        docId: widget.currentUser.docId ?? '',
        userId: email,
        name: widget.currentUser.name ?? (email.isEmpty ? 'User' : email.split('@').first),
        avatar: widget.currentUser.avatar ?? defaultAvatar(email),
        bio: widget.currentUser.bio,
        location: widget.currentUser.location,
        followers: List<String>.from(widget.currentUser.followers),
        following: List<String>.from(widget.currentUser.following),
        contactList: const [],
        audienceProfiles: const {},
      );
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
      _personalName.text = profile!.audienceProfiles[kAudiencePersonal]?.name ?? '';
      _personalBio.text = profile.audienceProfiles[kAudiencePersonal]?.bio ?? '';
      _personalAvatarUrl = profile.audienceProfiles[kAudiencePersonal]?.avatar;
      _professionalName.text = profile.audienceProfiles[kAudienceWork]?.name ?? '';
      _professionalBio.text = profile.audienceProfiles[kAudienceWork]?.bio ?? '';
      _professionalAvatarUrl = profile.audienceProfiles[kAudienceWork]?.avatar;
    });
  }

  Future<void> _pickPhoto(String audienceKey) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    final ext = x.path.split('.').last;
    final filename = 'avatar_${audienceKey}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final url = await uploadFileFromBytes(bytes, filename);
    if (url == null || !mounted) return;
    setState(() {
      switch (audienceKey) {
        case kAudienceDefault:
          _defaultAvatarUrl = url;
          break;
        case kAudiencePersonal:
          _personalAvatarUrl = url;
          break;
        case kAudienceWork:
          _professionalAvatarUrl = url;
          break;
      }
    });
  }

  Future<void> _save() async {
    var profile = _profile;
    if (profile == null || _saving) return;
    setState(() => _saving = true);
    try {
      var docId = profile.docId.trim();
      if (docId.isEmpty) {
        final ensured = await syncProfile(widget.currentUser).timeout(const Duration(seconds: 15));
        if (ensured != null) {
          profile = ensured;
          _profile = ensured;
          docId = ensured.docId.trim();
        } else {
          final email = (widget.currentUser.email ?? '').trim().toLowerCase();
          final existing = email.isEmpty ? null : await getProfileByUserId(email).timeout(const Duration(seconds: 8));
          if (existing != null) {
            profile = existing;
            _profile = existing;
            docId = existing.docId.trim();
          }
        }
      }
      if (docId.isEmpty) {
        throw Exception('Profile document unavailable');
      }
      final defaultName = _defaultName.text.trim();
      final defaultBio = _defaultBio.text.trim();
      await updateProfile(docId, {
        'name': defaultName.isEmpty ? (widget.currentUser.email ?? '').split('@').first : defaultName,
        'bio': defaultBio.isEmpty ? null : defaultBio,
        if (_defaultAvatarUrl != null && _defaultAvatarUrl!.isNotEmpty) 'avatar': _defaultAvatarUrl,
        'audienceProfiles': <String, AudienceProfile>{
          kAudiencePersonal: AudienceProfile(
            type: kAudiencePersonal,
            name: _personalName.text.trim().isEmpty ? null : _personalName.text.trim(),
            bio: _personalBio.text.trim().isEmpty ? null : _personalBio.text.trim(),
            avatar: _personalAvatarUrl,
          ),
          kAudienceWork: AudienceProfile(
            type: kAudienceWork,
            name: _professionalName.text.trim().isEmpty ? null : _professionalName.text.trim(),
            bio: _professionalBio.text.trim().isEmpty ? null : _professionalBio.text.trim(),
            avatar: _professionalAvatarUrl,
          ),
        },
      });
      final updated = AuthUser(
        email: widget.currentUser.email,
        name: defaultName.isEmpty ? widget.currentUser.name : defaultName,
        avatar: _defaultAvatarUrl ?? widget.currentUser.avatar,
        docId: docId,
        bio: defaultBio.isEmpty ? null : defaultBio,
        location: widget.currentUser.location,
        followers: widget.currentUser.followers,
        following: widget.currentUser.following,
      );
      await storeUser(updated);
      if (mounted) {
        widget.onProfileUpdated(updated);
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('profile_saved')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(updated);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('failed_save_try_again')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  bool get _isDark => widget.isDark;
  Color get _surface => _isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
  Color get _textPrimary => _isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
  Color get _textMuted => _isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
  Color get _fill => _isDark ? BondhuTokens.inputBgDark : BondhuTokens.inputBgLight;

  Widget _buildAudienceSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _audienceChip(0, Icons.person_rounded),
          _audienceChip(1, Icons.favorite_rounded),
          _audienceChip(2, Icons.work_rounded),
        ],
      ),
    );
  }

  Widget _audienceChip(int index, IconData icon) {
    final isSelected = _selectedAudienceIndex == index;
    final accent = _accentForAudience(index, _isDark);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedAudienceIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected && _isDark
                ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? (index == 0 ? Colors.black : Colors.white) : _textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                _audienceLabel(index),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? (index == 0 ? Colors.black : Colors.white) : _textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _audienceLabel(int index) {
    switch (index) {
      case 0:
        return AppLanguageService.instance.t('profile_audience_default');
      case 1:
        return AppLanguageService.instance.t('profile_audience_personal');
      case 2:
        return AppLanguageService.instance.t('profile_audience_professional');
      default:
        return '';
    }
  }

  String _audienceSubtitle(int index) {
    switch (index) {
      case 0:
        return AppLanguageService.instance.t('who_sees_default');
      case 1:
        return AppLanguageService.instance.t('who_sees_personal');
      case 2:
        return AppLanguageService.instance.t('who_sees_professional');
      default:
        return '';
    }
  }

  TextEditingController _nameController(int index) {
    switch (index) {
      case 0:
        return _defaultName;
      case 1:
        return _personalName;
      case 2:
        return _professionalName;
      default:
        return _defaultName;
    }
  }

  TextEditingController _bioController(int index) {
    switch (index) {
      case 0:
        return _defaultBio;
      case 1:
        return _personalBio;
      case 2:
        return _professionalBio;
      default:
        return _defaultBio;
    }
  }

  String? _avatarUrl(int index) {
    switch (index) {
      case 0:
        return _defaultAvatarUrl;
      case 1:
        return _personalAvatarUrl;
      case 2:
        return _professionalAvatarUrl;
      default:
        return _defaultAvatarUrl;
    }
  }

  String _audienceKey(int index) {
    switch (index) {
      case 0:
        return kAudienceDefault;
      case 1:
        return kAudiencePersonal;
      case 2:
        return kAudienceWork;
      default:
        return kAudienceDefault;
    }
  }

  IconData _audienceIcon(int index) {
    switch (index) {
      case 0:
        return Icons.person_rounded;
      case 1:
        return Icons.favorite_rounded;
      case 2:
        return Icons.work_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Widget _buildSaveButton() {
    final accent = _accentForAudience(_selectedAudienceIndex, _isDark);
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _selectedAudienceIndex == 0 ? Colors.black : Colors.white,
          elevation: _isDark ? 0 : 1,
          shadowColor: accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _saving
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _selectedAudienceIndex == 0 ? Colors.black54 : Colors.white70,
                ),
              )
            : Text(
                AppLanguageService.instance.t('save_changes'),
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: _textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLanguageService.instance.t('profile_by_audience'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BondhuTokens.primary))
          : _profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: _textMuted),
                        const SizedBox(height: 16),
                        Text(
                          AppLanguageService.instance.t('failed_save_try_again'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted),
                        ),
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: _loadProfile,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(AppLanguageService.instance.t('retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero: soft gradient strip (both themes)
                  Container(
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          BondhuTokens.primary.withValues(alpha: _isDark ? 0.6 : 0.5),
                          const Color(0xFFE11D48).withValues(alpha: _isDark ? 0.5 : 0.4),
                          const Color(0xFF6366F1).withValues(alpha: _isDark ? 0.5 : 0.4),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Text(
                    AppLanguageService.instance.t('profile_by_audience_hint'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _textMuted,
                      height: 1.45,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Section label
                  Text(
                    'CHOOSE AUDIENCE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildAudienceSwitcher(),
                  const SizedBox(height: 24),
                  // Single profile card for selected audience
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _profileBlock(
                      key: ValueKey<int>(_selectedAudienceIndex),
                      label: _audienceLabel(_selectedAudienceIndex),
                      subtitle: _audienceSubtitle(_selectedAudienceIndex),
                      nameController: _nameController(_selectedAudienceIndex),
                      bioController: _bioController(_selectedAudienceIndex),
                      avatarUrl: _avatarUrl(_selectedAudienceIndex),
                      audienceKey: _audienceKey(_selectedAudienceIndex),
                      icon: _audienceIcon(_selectedAudienceIndex),
                      accent: _accentForAudience(_selectedAudienceIndex, _isDark),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _whoSeesSection(),
                  const SizedBox(height: 28),
                  _buildSaveButton(),
                ],
              ),
            ),
    );
  }

  Widget _profileBlock({
    Key? key,
    required String label,
    required String subtitle,
    required TextEditingController nameController,
    required TextEditingController bioController,
    required String? avatarUrl,
    required String audienceKey,
    required IconData icon,
    required Color accent,
  }) {
    final isLightAccent = accent == BondhuTokens.primary;
    return Container(
      key: key,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
          width: 1,
        ),
        boxShadow: _isDark
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: _isDark ? 0.22 : 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => _pickPhoto(audienceKey),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withValues(alpha: 0.5), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: _isDark ? 0.2 : 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _avatarPlaceholder(icon, accent),
                            )
                          : _avatarPlaceholder(icon, accent),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 16,
                        color: isLightAccent ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _inputLabel(AppLanguageService.instance.t('full_name')),
          const SizedBox(height: 6),
          _textField(nameController, hint: AppLanguageService.instance.t('full_name'), accent: accent),
          const SizedBox(height: 14),
          _inputLabel(AppLanguageService.instance.t('about_me')),
          const SizedBox(height: 6),
          _textFieldMultiline(bioController, hint: AppLanguageService.instance.t('notes_placeholder'), accent: accent),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder(IconData icon, Color accent) {
    return Container(
      color: _fill,
      child: Icon(icon, size: 36, color: accent.withValues(alpha: 0.6)),
    );
  }

  Widget _inputLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: _textMuted),
    );
  }

  Widget _textField(TextEditingController controller, {String? hint, Color? accent}) {
    final focusColor = accent ?? BondhuTokens.primary;
    return TextField(
      controller: controller,
      style: GoogleFonts.plusJakartaSans(fontSize: 15, color: _textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: _textMuted.withValues(alpha: 0.7)),
        filled: true,
        fillColor: _fill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _textFieldMultiline(TextEditingController controller, {String? hint, Color? accent}) {
    final focusColor = accent ?? BondhuTokens.primary;
    return TextField(
      controller: controller,
      maxLines: 3,
      style: GoogleFonts.plusJakartaSans(fontSize: 15, color: _textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: _textMuted.withValues(alpha: 0.7)),
        filled: true,
        fillColor: _fill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _whoSeesSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _isDark
            ? BondhuTokens.surfaceDarkHover
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            width: 4,
            color: BondhuTokens.primary.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, size: 18, color: BondhuTokens.primary),
              const SizedBox(width: 8),
              Text(
                AppLanguageService.instance.t('who_sees_which_profile'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _whoSeesRow(
            AppLanguageService.instance.t('who_sees_default'),
            AppLanguageService.instance.t('profile_audience_default'),
          ),
          const SizedBox(height: 6),
          _whoSeesRow(
            AppLanguageService.instance.t('who_sees_personal'),
            AppLanguageService.instance.t('profile_audience_personal'),
          ),
          const SizedBox(height: 6),
          _whoSeesRow(
            AppLanguageService.instance.t('who_sees_professional'),
            AppLanguageService.instance.t('profile_audience_professional'),
          ),
        ],
      ),
    );
  }

  Widget _whoSeesRow(String who, String profileLabel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: BondhuTokens.primary),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted, height: 1.4),
              children: [
                TextSpan(text: who),
                TextSpan(
                  text: ' → $profileLabel',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: BondhuTokens.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
