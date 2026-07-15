import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../controllers/clipboard_controller.dart';
import '../../providers/app_state.dart';
import '../../ui/theme/app_theme.dart';
import '../../widgets/liquid_background.dart';

class SettingsPage extends StatelessWidget {
  final VoidCallback onResetApp;
  final EdgeInsets? padding;

  const SettingsPage({
    super.key,
    required this.onResetApp,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, ClipboardController>(
      builder: (context, appState, clipboardController, _) {
        final scheme = Theme.of(context).colorScheme;

        return LiquidBackground(
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: padding ?? EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 100),
              children: [
                Text('Settings', style: Theme.of(context).textTheme.headlineMedium)
                    .animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 20),

                // Device info
                _DeviceInfoCard(
                  deviceName: appState.deviceName,
                  deviceId: appState.deviceId,
                  onRename: () => _showRenameDialog(context, appState),
                ),
                const SizedBox(height: 16),

                // Sync settings
                _SettingsGroup(
                  title: 'Sync',
                  children: [
                    _ToggleRow(
                      icon: Icons.content_paste_rounded,
                      title: 'Clipboard sync',
                      value: !clipboardController.isSyncPaused,
                      onChanged: (v) => clipboardController.setSyncPaused(!v),
                    ),
                    _ToggleRow(
                      icon: Icons.notifications_rounded,
                      title: 'Notification sync',
                      value: appState.notificationSyncEnabled,
                      onChanged: (v) => appState.toggleSetting('notification_sync_enabled', v),
                    ),
                    _ToggleRow(
                      icon: Icons.radar_rounded,
                      title: 'Auto discovery',
                      value: appState.discoveryEnabled,
                      onChanged: (v) => appState.toggleSetting('discovery_enabled', v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Appearance
                _SettingsGroup(
                  title: 'Appearance',
                  children: [
                    _ThemePicker(),
                  ],
                ),
                const SizedBox(height: 16),

                // Platform-specific
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) ...[
                  _SettingsGroup(
                    title: 'macOS',
                    children: [
                      _ToggleRow(
                        icon: Icons.launch_rounded,
                        title: 'Start at login',
                        value: appState.launchAtStartupEnabled,
                        onChanged: appState.toggleLaunchAtStartup,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Danger zone
                _SettingsGroup(
                  title: 'Data',
                  children: [
                    _ActionRow(
                      icon: Icons.delete_sweep_rounded,
                      title: 'Clear history',
                      onTap: () async {
                        await appState.clearHistory();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('History cleared')),
                          );
                        }
                      },
                    ),
                    _ActionRow(
                      icon: Icons.restart_alt_rounded,
                      title: 'Reset app',
                      isDestructive: true,
                      onTap: () => _showResetDialog(context),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'Wire v1.0.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context, AppState appState) async {
    final controller = TextEditingController(text: appState.deviceName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Device name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await appState.renameLocalDevice(result);
    }
  }

  Future<void> _showResetDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset app?'),
        content: const Text('This removes all data, pairing, and settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) onResetApp();
  }
}

// ─── Device Info Card ──────────────────────────────────────────────────────────

class _DeviceInfoCard extends StatelessWidget {
  final String deviceName;
  final String deviceId;
  final VoidCallback onRename;

  const _DeviceInfoCard({
    required this.deviceName,
    required this.deviceId,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = deviceName.isNotEmpty ? deviceName[0].toUpperCase() : 'W';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deviceName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  deviceId.substring(0, 8).toUpperCase(),
                  style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.35)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRename,
            icon: const Icon(Icons.edit_rounded, size: 18),
            style: IconButton.styleFrom(foregroundColor: scheme.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }
}

// ─── Settings Group ────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.28),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 52,
                    color: scheme.outline.withValues(alpha: 0.3),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Toggle Row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 14)),
          ),
          SizedBox(
            height: 32,
            child: FittedBox(
              child: Switch.adaptive(
                value: value,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Row ────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isDestructive ? Colors.redAccent : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color.withValues(alpha: isDestructive ? 0.7 : 0.45)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDestructive ? Colors.redAccent.withValues(alpha: 0.8) : null,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurface.withValues(alpha: 0.15)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Theme Picker ──────────────────────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentMode = AppTheme.currentThemeMode;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _ThemeOption(
            label: 'Auto',
            icon: Icons.brightness_auto_rounded,
            isSelected: currentMode == ThemeMode.system,
            onTap: () => AppTheme.setThemeMode(ThemeMode.system),
          ),
          const SizedBox(width: 8),
          _ThemeOption(
            label: 'Light',
            icon: Icons.light_mode_rounded,
            isSelected: currentMode == ThemeMode.light,
            onTap: () => AppTheme.setThemeMode(ThemeMode.light),
          ),
          const SizedBox(width: 8),
          _ThemeOption(
            label: 'Dark',
            icon: Icons.dark_mode_rounded,
            isSelected: currentMode == ThemeMode.dark,
            onTap: () => AppTheme.setThemeMode(ThemeMode.dark),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.1)
                : scheme.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? scheme.primary.withValues(alpha: 0.25) : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
