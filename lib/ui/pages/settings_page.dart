import 'package:flutter/material.dart';
import '../widgets/glass_card.dart';
import '../widgets/confirmation_dialog.dart';

class SettingsPage extends StatelessWidget {
  final bool autoConnect;
  final bool discoveryEnabled;
  final bool clipboardSync;
  final bool notificationSync;
  final bool transferHistory;
  final bool silentClipboard;
  final bool labsMirrorFeatures;
  final bool labsStudentHub;
  final bool labsMountFinder;
  final String deviceId;
  final ThemeMode themeMode;
  final VoidCallback? onHideApp;
  final VoidCallback onClearClipboardHistory;
  final VoidCallback onClearTransferHistory;
  final VoidCallback? onClearNotificationHistory;
  final Function(ThemeMode) onThemeModeChanged;
  final Function(bool) onToggleAutoConnect;
  final Function(bool) onToggleDiscovery;
  final Function(bool) onToggleClipboardSync;
  final Function(bool) onToggleNotificationSync;
  final Function(bool) onToggleTransferHistory;
  final Function(bool) onToggleSilentClipboard;
  final Function(bool) onToggleLabsMirrorFeatures;
  final Function(bool) onToggleLabsStudentHub;
  final Function(bool) onToggleLabsMountFinder;

  const SettingsPage({
    super.key,
    required this.autoConnect,
    required this.discoveryEnabled,
    required this.clipboardSync,
    required this.notificationSync,
    required this.transferHistory,
    required this.silentClipboard,
    required this.labsMirrorFeatures,
    required this.labsStudentHub,
    required this.labsMountFinder,
    required this.deviceId,
    required this.themeMode,
    this.onHideApp,
    required this.onClearClipboardHistory,
    required this.onClearTransferHistory,
    this.onClearNotificationHistory,
    required this.onThemeModeChanged,
    required this.onToggleAutoConnect,
    required this.onToggleDiscovery,
    required this.onToggleClipboardSync,
    required this.onToggleNotificationSync,
    required this.onToggleTransferHistory,
    required this.onToggleSilentClipboard,
    required this.onToggleLabsMirrorFeatures,
    required this.onToggleLabsStudentHub,
    required this.onToggleLabsMountFinder,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Personalize appearance, behavior, and power tools.',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: isDark ? 0.4 : 0.24),
                  ),
                ),
                child: Icon(Icons.tune_rounded, color: scheme.primary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              _buildSettingSection(
                context: context,
                title: 'Appearance',
                children: [
                  GlassCard(
                    accent: scheme.secondary,
                    borderRadius: 20,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theme Mode',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          selected: {themeMode},
                          onSelectionChanged: (value) {
                            onThemeModeChanged(value.first);
                          },
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.auto_mode_rounded),
                              label: Text('System'),
                            ),
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
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSettingSection(
                context: context,
                title: 'Connectivity',
                children: [
                  _buildSettingItem(
                    context: context,
                    title: 'Auto Connect',
                    subtitle: 'Reconnect to last peer on startup',
                    value: autoConnect,
                    onChanged: onToggleAutoConnect,
                    icon: Icons.sync,
                  ),
                  _buildSettingItem(
                    context: context,
                    title: 'Device Discovery',
                    subtitle: 'Allow other devices to find you',
                    value: discoveryEnabled,
                    onChanged: onToggleDiscovery,
                    icon: Icons.wifi_tethering_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSettingSection(
                context: context,
                title: 'Data Sync',
                children: [
                  _buildSettingItem(
                    context: context,
                    title: 'Clipboard Sync',
                    subtitle: 'Synchronize clipboard across devices',
                    value: clipboardSync,
                    onChanged: onToggleClipboardSync,
                    icon: Icons.content_paste_go_rounded,
                  ),
                  _buildSettingItem(
                    context: context,
                    title: 'Notification Sync',
                    subtitle: 'Forward phone notifications to Mac',
                    value: notificationSync,
                    onChanged: onToggleNotificationSync,
                    icon: Icons.notifications_active_rounded,
                  ),
                  _buildSettingItem(
                    context: context,
                    title: 'Transfer History',
                    subtitle: 'Keep a record of shared files',
                    value: transferHistory,
                    onChanged: onToggleTransferHistory,
                    icon: Icons.history_rounded,
                  ),
                  _buildSettingItem(
                    context: context,
                    title: 'Silent Clipboard',
                    subtitle: 'Sync silently — like Apple Universal Clipboard',
                    value: silentClipboard,
                    onChanged: onToggleSilentClipboard,
                    icon: Icons.notifications_paused_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSettingSection(
                context: context,
                title: 'Utilities',
                children: [
                  _buildActionItem(
                    context: context,
                    title: 'Clear Clipboard History',
                    subtitle: 'Delete all locally stored clipboard entries',
                    icon: Icons.cleaning_services_rounded,
                    onTap: () async {
                      final confirmed = await ConfirmationDialog.show(
                        context,
                        title: 'Clear Clipboard History?',
                        message: 'This will permanently delete all clipboard entries. This action cannot be undone.',
                        confirmText: 'Clear',
                        icon: Icons.delete_forever_rounded,
                        iconColor: const Color(0xFFF97316),
                      );
                      if (confirmed == true) {
                        onClearClipboardHistory();
                      }
                    },
                    tint: const Color(0xFFF97316),
                  ),
                  _buildActionItem(
                    context: context,
                    title: 'Clear Transfer History',
                    subtitle: 'Remove completed and failed transfer logs',
                    icon: Icons.layers_clear_rounded,
                    onTap: () async {
                      final confirmed = await ConfirmationDialog.show(
                        context,
                        title: 'Clear Transfer History?',
                        message: 'All file transfer logs will be permanently deleted. This action cannot be undone.',
                        confirmText: 'Clear',
                        icon: Icons.delete_forever_rounded,
                        iconColor: const Color(0xFFDC2626),
                      );
                      if (confirmed == true) {
                        onClearTransferHistory();
                      }
                    },
                    tint: const Color(0xFFDC2626),
                  ),
                  if (onClearNotificationHistory != null)
                    _buildActionItem(
                      context: context,
                      title: 'Clear Notification History',
                      subtitle: 'Reset synced notification timeline',
                      icon: Icons.notifications_off_rounded,
                      onTap: () async {
                        final confirmed = await ConfirmationDialog.show(
                          context,
                          title: 'Clear Notification History?',
                          message: 'This will remove all synced notification records. This action cannot be undone.',
                          confirmText: 'Clear',
                          icon: Icons.delete_forever_rounded,
                          iconColor: const Color(0xFF7C3AED),
                        );
                        if (confirmed == true) {
                          onClearNotificationHistory!();
                        }
                      },
                      tint: const Color(0xFF7C3AED),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSettingSection(
                context: context,
                title: 'Labs',
                children: [
                  _buildSettingItem(
                    context: context,
                    title: 'Mirror Features (Experimental)',
                    subtitle: 'Keyboard and camera mirror reliability mode',
                    value: labsMirrorFeatures,
                    onChanged: onToggleLabsMirrorFeatures,
                    icon: Icons.auto_awesome_rounded,
                  ),
                  _buildSettingItem(
                    context: context,
                    title: 'Student Hub (Experimental)',
                    subtitle: 'Enable extended study workspace panel',
                    value: labsStudentHub,
                    onChanged: onToggleLabsStudentHub,
                    icon: Icons.school_rounded,
                  ),
                  _buildSettingItem(
                    context: context,
                    title: 'Finder Mount (Experimental)',
                    subtitle: 'Enable Android storage mount in Finder',
                    value: labsMountFinder,
                    onChanged: onToggleLabsMountFinder,
                    icon: Icons.usb_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (onHideApp != null)
                _buildSettingSection(
                  context: context,
                  title: 'macOS Options',
                  children: [
                    _buildActionItem(
                      context: context,
                      title: 'Hide to Menu Bar',
                      subtitle: 'Keep app running while hidden',
                      icon: Icons.visibility_off_rounded,
                      onTap: onHideApp!,
                      tint: scheme.primary,
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              _buildSettingSection(
                context: context,
                title: 'Device Info',
                children: [
                  GlassCard(
                    accent: scheme.secondary,
                    borderRadius: 20,
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEVICE ID',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.48),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          deviceId,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 14,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSettingSection(
                context: context,
                title: 'About',
                children: [
                  GlassCard(
                    accent: scheme.tertiary,
                    borderRadius: 20,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.9),
                                    scheme.secondary.withValues(alpha: 0.7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Icon(
                                Icons.cable_rounded,
                                color: scheme.onPrimary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Wire Sync',
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Version 1.0.0 (Build 1)',
                                    style: TextStyle(
                                      color: scheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Cross-device clipboard, file transfer, and continuity engine. Seamlessly sync and control between your Mac and Android devices.',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Divider(color: scheme.outline.withValues(alpha: 0.2)),
                        const SizedBox(height: 8),
                        Text(
                          '© 2026 Sagar M. All rights reserved.',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.42),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.56),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSettingItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        accent: value ? scheme.primary : null,
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: (value ? scheme.primary : scheme.outline).withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: value ? scheme.primary : scheme.onSurface, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          trailing: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: scheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required Color tint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 18,
        accent: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tint.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: tint, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
