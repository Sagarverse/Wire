import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import '../widgets/glass_card.dart';
import '../../widgets/liquid_background.dart';
import '../../providers/app_state.dart';
import '../../controllers/clipboard_controller.dart';
import '../../providers/file_transfer_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import 'device_pairing_page.dart';
import '../widgets/qr_pairing_dialog.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../../services/permissions_service.dart';

class SettingsPage extends StatelessWidget {
  final VoidCallback onResetApp;
  final EdgeInsets? padding;

  const SettingsPage({super.key, required this.onResetApp, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer3<AppState, ClipboardController, FileTransferProvider>(
      builder: (context, appState, clipboardController, fileTransferProvider, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: LiquidBackground(
            child: Padding(
              padding: padding ?? const EdgeInsets.only(bottom: 120),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 32),
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                          letterSpacing: -1.0,
                        ),
                      ),
                    ),
                    _buildSection(
                      context,
                      title: 'My Profile',
                      icon: Icons.account_circle_rounded,
                      children: [
                        _buildProfileTile(context, appState),
                        _buildActionTile(
                          context,
                          title: 'Device Identity',
                          subtitle: 'Current Name: ${appState.deviceName}',
                          icon: Icons.edit_note_rounded,
                          onTap: () => _showDeviceRenameDialog(context, appState),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Pairing & Devices',
                      icon: Icons.phonelink_setup_rounded,
                      children: [
                        _buildActionTile(
                          context,
                          title: 'Manage Linked Devices',
                          subtitle: appState.pairingService.activeDevice != null
                              ? 'Connected to ${appState.pairingService.activeDevice!.name}'
                              : 'No active device linked',
                          icon: Icons.devices_other_rounded,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DevicePairingPage(
                                  pairingService: appState.pairingService,
                                  discoveredPeers: appState.discoveredPeers,
                                  localDeviceId: appState.deviceId,
                                  onMakeActive: (device) =>
                                      appState.connectToPeer(
                                        device.lastIp,
                                        targetId: device.deviceId,
                                      ),
                                  onConnectToPeer: (peer) =>
                                      appState.connectToPeer(
                                        peer.address,
                                        targetId: peer.deviceId,
                                      ),
                                ),
                              ),
                            );
                          },
                        ),
                        _buildActionTile(
                          context,
                          title: 'Share Pairing Code',
                          subtitle: 'Show QR code for other devices to scan',
                          icon: Icons.qr_code_2_rounded,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => QrPairingDialog(
                                deviceId: appState.deviceId,
                                deviceName: (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)
                                    ? 'Wire Mac'
                                    : 'Wire Device',
                                port: 5757,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildPermissionSection(context, appState),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Appearance',
                      icon: Icons.palette_rounded,
                      children: [_buildThemeSwitcher(context)],
                    ),

                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Connectivity',
                      icon: Icons.wifi_tethering_rounded,
                      children: [
                        _buildToggleTile(
                          context,
                          title: 'Auto-Connect',
                          subtitle: 'Pair with last device on startup',
                          value: appState.autoConnectEnabled,
                          onChanged: (v) =>
                              appState.toggleSetting('auto_connect', v),
                          icon: Icons.bolt_rounded,
                        ),
                        _buildToggleTile(
                          context,
                          title: 'Discovery',
                          subtitle: 'Visible to other Wire devices',
                          value: appState.discoveryEnabled,
                          onChanged: (v) =>
                              appState.toggleSetting('discovery_enabled', v),
                          icon: Icons.visibility_rounded,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Data Sync',
                      icon: Icons.sync_rounded,
                      children: [
                        _buildToggleTile(
                          context,
                          title: 'Clipboard',
                          subtitle: 'Sync text across devices',
                          value: !appState.isSyncPaused,
                          onChanged: (v) =>
                              appState.toggleSetting('sync_paused', !v),
                          icon: Icons.content_paste_go_rounded,
                        ),
                        _buildToggleTile(
                          context,
                          title: 'Notifications',
                          subtitle: 'Forward mobile alerts to desktop',
                          value: appState.notificationSyncEnabled,
                          onChanged: (v) => appState.toggleSetting(
                            'notification_sync_enabled',
                            v,
                          ),
                          icon: Icons.notifications_active_rounded,
                        ),
                        _buildToggleTile(
                          context,
                          title: 'Silent Mode',
                          subtitle: 'No popups for clipboard sync',
                          value: appState.silentClipboard,
                          onChanged: (v) =>
                              appState.toggleSetting('silent_clipboard', v),
                          icon: Icons.notifications_paused_rounded,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Storage',
                      icon: Icons.folder_open_rounded,
                      children: [
                        _buildActionTile(
                          context,
                          title: 'Downloads Root',
                          subtitle:
                              appState.downloadsPath ??
                              'Default (~/Downloads/Wire)',
                          icon: Icons.folder_special_rounded,
                          onTap: () async {
                            String? result = await FilePicker.platform
                                .getDirectoryPath();
                            if (result != null) {
                              appState.updateDownloadsPath(result);
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Experimental Labs',
                      icon: Icons.science_rounded,
                      accent: scheme.onSurface.withValues(alpha: 0.6),
                      children: [
                        _buildToggleTile(
                          context,
                          title: 'Finder Mount',
                          subtitle: 'Mount phone storage in macOS Finder',
                          value: appState.labsMountFinderEnabled,
                          onChanged: (v) => appState.toggleSetting(
                            'labs_mount_finder_enabled',
                            v,
                          ),
                          icon: Icons.usb_rounded,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Maintenance',
                      icon: Icons.cleaning_services_rounded,
                      children: [
                        _buildActionTile(
                          context,
                          title: 'Clear Clipboard',
                          subtitle: 'Delete locally cached text data',
                          onTap: () => clipboardController.clearHistory(),
                          icon: Icons.delete_sweep_rounded,
                          isDestructive: true,
                        ),
                        _buildActionTile(
                          context,
                          title: 'Reset Transfers',
                          subtitle: 'Clear all file transfer logs',
                          onTap: () => fileTransferProvider.clearHistory(),
                          icon: Icons.history_rounded,
                          isDestructive: true,
                        ),
                        _buildActionTile(
                          context,
                          title: 'Restart Experience',
                          subtitle: 'Delete all app data & re-pair',
                          onTap: () => _showResetDialog(context),
                          icon: Icons.restart_alt_rounded,
                          isDestructive: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                    _buildAboutSection(context),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: (accent ?? scheme.primary).withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: (accent ?? scheme.onSurface)
                      .withValues(alpha: 0.7),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(24),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildToggleTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      secondary: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (value ? scheme.primary : scheme.onSurface).withValues(
            alpha: 0.1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: value ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required IconData icon,
    bool isDestructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isDestructive ? scheme.error : scheme.onSurface;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      ),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: scheme.onSurface.withValues(alpha: 0.2),
      ),
    );
  }

  Widget _buildThemeSwitcher(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, themeMode, _) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              selected: {themeMode},
              onSelectionChanged: (val) => AppTheme.setThemeMode(val.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.transparent,
                selectedBackgroundColor: scheme.onSurface,
                selectedForegroundColor: scheme.surface,
                side: BorderSide.none,
              ),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.auto_mode_rounded),
                  label: Text('Auto'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.bolt_rounded,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Wire Sync',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Local-first device continuity',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.45),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'v1.0.0 · Production',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.4),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAboutLink(Icons.language_rounded, 'Website'),
              const SizedBox(width: 40),
              _buildAboutLink(Icons.help_outline_rounded, 'Manual'),
              const SizedBox(width: 40),
              _buildAboutLink(Icons.privacy_tip_rounded, 'Privacy'),
            ],
          ),
          const SizedBox(height: 60),
          Text(
            'Crafted with care · Local-first · Private',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.3),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutLink(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.grey.withValues(alpha: 0.6)),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionSection(BuildContext context, AppState appState) {
    final permissions = PermissionsService();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.security_rounded,
                size: 16,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'SYSTEM PERMISSIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary.withValues(alpha: 0.7),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(24),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  _buildPermissionTile(
                    context,
                    title: 'Connectivity',
                    subtitle: 'Nearby device discovery',
                    permission: Permission.bluetoothScan,
                    onGrant: () async {
                      await permissions.requestBluetooth();
                      setState(() {});
                    },
                  ),
                  _buildPermissionTile(
                    context,
                    title: 'Messaging',
                    subtitle: 'Sync SMS & contacts',
                    permission: Permission.sms,
                    onGrant: () async {
                      await permissions.requestSms();
                      setState(() {});
                    },
                  ),
                  _buildPermissionTile(
                    context,
                    title: 'Notifications',
                    subtitle: 'Real-time sync alerts',
                    permission: Permission.notification,
                    onGrant: () async {
                      await permissions.requestNotifications();
                      setState(() {});
                    },
                  ),
                  _buildPermissionTile(
                    context,
                    title: 'Storage',
                    subtitle: 'File sharing access',
                    permission: Permission.storage,
                    onGrant: () async {
                      await permissions.requestStorage();
                      setState(() {});
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Permission permission,
    required VoidCallback onGrant,
  }) {
    final permissions = PermissionsService();
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<bool>(
      future: permissions.checkPermissionStatus(permission),
      builder: (context, snapshot) {
        final isGranted = snapshot.data == true;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isGranted ? Colors.green : scheme.onSurface).withValues(
                alpha: 0.1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isGranted
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: isGranted
                  ? Colors.green
                  : scheme.onSurface.withValues(alpha: 0.4),
              size: 22,
            ),
          ),
          trailing: isGranted
              ? null
              : TextButton(onPressed: onGrant, child: const Text('GRANT')),
        );
      },
    );
  }

  Widget _buildProfileTile(BuildContext context, AppState appState) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onTap: () => _showProfileEditDialog(context, appState),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
          image: appState.userAvatar != null ? DecorationImage(image: NetworkImage(appState.userAvatar!)) : null,
        ),
        child: appState.userAvatar == null ? Icon(Icons.person_rounded, color: scheme.onPrimary) : null,
      ),
      title: Text(
        appState.userName,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      subtitle: Text(
        'Tap to edit name or avatar',
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 13),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.2)),
    );
  }

  void _showProfileEditDialog(BuildContext context, AppState appState) {
    final nameController = TextEditingController(text: appState.userName);
    final avatarController = TextEditingController(text: appState.userAvatar ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Display Name', hintText: 'Enter your name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: avatarController,
              decoration: const InputDecoration(labelText: 'Avatar URL', hintText: 'https://...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              appState.updateProfile(name: nameController.text, avatar: avatarController.text.isEmpty ? null : avatarController.text);
              Navigator.pop(context);
            },
            child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeviceRenameDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController(text: appState.deviceName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Rename Local Device'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Device Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              appState.renameLocalDevice(controller.text);
              Navigator.pop(context);
            },
            child: const Text('RENAME', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Factory Reset?'),
        content: const Text(
          'This will delete all pairing data, custom settings, and transfer history.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onResetApp();
            },
            child: const Text(
              'RESET EVERYTHING',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
