import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/google_drive_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/friendly_error_message.dart';
import '../../auth/data/auth_providers.dart';
import '../../kanban/data/kanban_providers.dart';

final currentUserProfileProvider = FutureProvider.autoDispose<UserProfile?>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return null;
  }

  final row =
      await ref
          .watch(supabaseClientProvider)
          .from('user_profiles')
          .select('user_id, username, display_name, avatar_url')
          .eq('user_id', user.id)
          .maybeSingle();

  if (row == null) {
    return null;
  }

  return UserProfile.fromRow(row);
});

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    return UserProfile(
      userId: row['user_id'] as String,
      username: row['username'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Google Drive OAuth is intentionally paused. To re-enable it:
  // 1. Enable Google in Supabase Auth providers with a Google OAuth web client.
  // 2. Add https://hirwocyixlhjlsrlygiz.supabase.co/auth/v1/callback to
  //    the Google OAuth client's authorized redirect URIs.
  // 3. Add noggin://auth-callback to Supabase Auth redirect URLs.
  // 4. Enable Manual Linking in Supabase Auth.
  // 5. Either verify the Google OAuth app for Drive metadata scopes or keep
  //    the app in Testing mode and add every tester under Google test users.
  // 6. Set _googleDriveOAuthEnabled to true and test the full browser return.
  static const bool _googleDriveOAuthEnabled = false;

  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  String? _loadedProfileUserId;
  bool _savingProfile = false;
  bool _uploadingAvatar = false;
  bool _connectingGoogleDrive = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final profileValue = ref.watch(currentUserProfileProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final googleIdentity = user?.identities?.where(
      (identity) => identity.provider == OAuthProvider.google.name,
    );
    final connectedIdentity =
        googleIdentity == null || googleIdentity.isEmpty
            ? null
            : googleIdentity.first;
    final googleEmail = connectedIdentity?.identityData?['email'] as String?;
    final googleConnected = connectedIdentity != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
        backgroundColor: AppTheme.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _SettingsSection(
              title: 'Account',
              children: [
                profileValue.when(
                  loading:
                      () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                  error:
                      (error, _) => Text(
                        friendlyErrorMessage(
                          error,
                          fallback: 'Could not load your profile.',
                        ),
                        style: TextStyle(color: colorScheme.error),
                      ),
                  data: (profile) {
                    _syncProfileFields(user, profile);
                    return _ProfileForm(
                      email: user?.email ?? 'Signed in',
                      avatarUrl: profile?.avatarUrl,
                      displayNameController: _displayNameController,
                      usernameController: _usernameController,
                      saving: _savingProfile,
                      uploadingAvatar: _uploadingAvatar,
                      onPickAvatar: _pickAvatar,
                      onSave: _saveProfile,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'Integrations',
              children: [
                _SettingsTile(
                  leading: Icons.add_to_drive_rounded,
                  title: 'Google Drive',
                  subtitle:
                      googleConnected
                          ? 'Connected${googleEmail == null ? '' : ' as $googleEmail'}. Noggin can request Drive file metadata when Google permissions are available.'
                          : !_googleDriveOAuthEnabled
                          ? 'Google account connection is paused while OAuth verification is being configured. Drive links can still be saved and opened.'
                          : GoogleDriveConfig.hasApiKey
                          ? 'Public and shared Drive links can show file names. Connect Google for private Drive metadata access.'
                          : 'Drive links can be saved now. Connect Google for private file access, or add GOOGLE_DRIVE_API_KEY for public file names.',
                  trailing: _StatusPill(
                    label:
                        googleConnected
                            ? 'Connected'
                            : !_googleDriveOAuthEnabled
                            ? 'Paused'
                            : GoogleDriveConfig.hasApiKey
                            ? 'Link previews'
                            : 'Not connected',
                    color:
                        googleConnected
                            ? Colors.green.shade700
                            : !_googleDriveOAuthEnabled
                            ? colorScheme.outline
                            : GoogleDriveConfig.hasApiKey
                            ? colorScheme.primary
                            : colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed:
                        !_googleDriveOAuthEnabled ||
                                googleConnected ||
                                _connectingGoogleDrive
                            ? null
                            : _connectGoogleDrive,
                    icon:
                        _connectingGoogleDrive
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Icon(
                              googleConnected
                                  ? Icons.check_rounded
                                  : Icons.link_rounded,
                            ),
                    label: Text(
                      !_googleDriveOAuthEnabled
                          ? 'Google Drive connection paused'
                          : googleConnected
                          ? 'Google Drive connected'
                          : 'Connect Google Drive',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _googleDriveOAuthEnabled
                      ? 'Per-user Google sign-in will let each teammate use their own Drive access for private files.'
                      : 'Public or shared Drive links will still open from tasks and messages.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _syncProfileFields(User? user, UserProfile? profile) {
    final userId = user?.id;
    if (userId == null || _loadedProfileUserId == userId) {
      return;
    }

    _loadedProfileUserId = userId;
    final emailPrefix = user?.email?.split('@').first ?? '';
    _displayNameController.text =
        profile?.displayName.trim().isNotEmpty == true
            ? profile!.displayName
            : emailPrefix;
    _usernameController.text =
        profile?.username.trim().isNotEmpty == true
            ? profile!.username
            : emailPrefix.toLowerCase();
  }

  Future<void> _saveProfile() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _savingProfile) {
      return;
    }

    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();

    if (displayName.isEmpty || displayName.length > 80) {
      _showMessage('Display name must be 1-80 characters.', isError: true);
      return;
    }

    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(username)) {
      _showMessage(
        'Username must be 3-24 lowercase letters, numbers, or underscores.',
        isError: true,
      );
      return;
    }

    setState(() => _savingProfile = true);
    try {
      await ref
          .read(supabaseClientProvider)
          .from('user_profiles')
          .update({'display_name': displayName, 'username': username})
          .eq('user_id', user.id);

      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(boardMembersProvider);

      if (!mounted) {
        return;
      }

      _showMessage('Profile updated.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        friendlyErrorMessage(error, fallback: 'Could not update your profile.'),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _uploadingAvatar) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      _showMessage('Choose a profile photo under 5 MB.', isError: true);
      return;
    }

    final extension =
        (file.extension?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ??
                'jpg')
            .trim();
    final safeExtension = extension.isEmpty ? 'jpg' : extension;
    final contentType =
        safeExtension == 'png'
            ? 'image/png'
            : safeExtension == 'webp'
            ? 'image/webp'
            : safeExtension == 'gif'
            ? 'image/gif'
            : 'image/jpeg';
    final path =
        '${user.id}/avatar-${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

    setState(() => _uploadingAvatar = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      final avatarUrl = client.storage.from('avatars').getPublicUrl(path);

      await client
          .from('user_profiles')
          .update({'avatar_url': avatarUrl})
          .eq('user_id', user.id);

      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(boardMembersProvider);

      if (!mounted) {
        return;
      }
      _showMessage('Profile photo updated.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        friendlyErrorMessage(
          error,
          fallback: 'Could not upload your profile photo.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _connectGoogleDrive() async {
    if (_connectingGoogleDrive) {
      return;
    }

    setState(() => _connectingGoogleDrive = true);
    try {
      final launched = await ref
          .read(supabaseClientProvider)
          .auth
          .linkIdentity(
            OAuthProvider.google,
            redirectTo: GoogleDriveConfig.oauthRedirectUrl,
            scopes: GoogleDriveConfig.oauthScopes,
            queryParams: GoogleDriveConfig.oauthQueryParams,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            launched
                ? 'Finish Google Drive connection in the browser.'
                : 'Could not open Google sign-in.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_googleDriveConnectionError(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _connectingGoogleDrive = false);
      }
    }
  }

  String _googleDriveConnectionError(Object error) {
    if (error is AuthException) {
      return error.message;
    }
    return 'Could not connect Google Drive.';
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.black87,
      ),
    );
  }
}

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.email,
    required this.avatarUrl,
    required this.displayNameController,
    required this.usernameController,
    required this.saving,
    required this.uploadingAvatar,
    required this.onPickAvatar,
    required this.onSave,
  });

  final String email;
  final String? avatarUrl;
  final TextEditingController displayNameController;
  final TextEditingController usernameController;
  final bool saving;
  final bool uploadingAvatar;
  final VoidCallback onPickAvatar;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage:
                      avatarUrl == null || avatarUrl!.isEmpty
                          ? null
                          : NetworkImage(avatarUrl!),
                  child:
                      avatarUrl == null || avatarUrl!.isEmpty
                          ? Icon(
                            Icons.person_outline_rounded,
                            color: colorScheme.onPrimaryContainer,
                          )
                          : null,
                ),
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: IconButton.filledTonal(
                    tooltip: 'Change photo',
                    onPressed: uploadingAvatar ? null : onPickAvatar,
                    icon:
                        uploadingAvatar
                            ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.camera_alt_rounded, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Noggin account',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: displayNameController,
          textInputAction: TextInputAction.next,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Display name',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: usernameController,
          textInputAction: TextInputAction.done,
          maxLength: 24,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixText: '@',
            prefixIcon: Icon(Icons.alternate_email_rounded),
            helperText: 'Lowercase letters, numbers, and underscores only.',
          ),
          onSubmitted: (_) => saving ? null : onSave(),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon:
                saving
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.save_rounded),
            label: const Text('Save Profile'),
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(leading, color: colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
