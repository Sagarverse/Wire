import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/clipboard_item.dart';
import '../widgets/glass_card.dart';
import '../widgets/status_dash.dart';
import '../widgets/tool_card.dart';
import '../widgets/media_control_card.dart';
import '../widgets/staggered_animated_item.dart';

class HomePage extends StatelessWidget {
  final String deviceName;
  final int batteryLevel;
  final bool isCharging;
  final String? peerName;
  final bool isPeerConnected;
  final int? remoteBattery;
  final bool? remoteIsCharging;
  final int? pingMs;
  final bool isSyncing;
  final String connectionHealthLabel;
  final String lastSyncLabel;
  final VoidCallback onReconnect;
  final bool labsMirrorEnabled;
  final bool labsStudentHubEnabled;
  final List<ClipboardItem> clipboardHistory;
  final bool focusMode;
  final VoidCallback onToggleFocus;
  final VoidCallback onMirrorKeyboard;
  final VoidCallback onHandoffUrl;
  final VoidCallback onStudentHub;
  final VoidCallback? onMirrorScreen;
  final VoidCallback? onFindPhone;
  final VoidCallback? onTrackpad;
  final VoidCallback? onRemoteCamera;
  final VoidCallback? onSms;
  final VoidCallback? onMountPhoneInFinder;
  final Function(String) onMediaAction;
  final Function(String) onClipboardCopy;
  final Function(String) onConnectToPeer;
  final VoidCallback onSendCurrentClipboard;
  final VoidCallback onSendClipboardFile;
  final VoidCallback onDevicesTapped;
  final Function(ClipboardItem)? onClearClipboardItem;
  final VoidCallback? onClearClipboardAll;
  final Future<void> Function()? onRefresh;

  const HomePage({
    super.key,
    required this.deviceName,
    required this.batteryLevel,
    required this.isCharging,
    this.peerName,
    this.isPeerConnected = false,
    this.remoteBattery,
    this.remoteIsCharging,
    this.pingMs,
    this.isSyncing = false,
    required this.connectionHealthLabel,
    required this.lastSyncLabel,
    required this.onReconnect,
    this.labsMirrorEnabled = true,
    this.labsStudentHubEnabled = true,
    required this.clipboardHistory,
    required this.focusMode,
    required this.onToggleFocus,
    required this.onMirrorKeyboard,
    required this.onHandoffUrl,
    required this.onStudentHub,
    this.onMirrorScreen,
    this.onFindPhone,
    this.onTrackpad,
    this.onRemoteCamera,
    this.onSms,
    this.onMountPhoneInFinder,
    required this.onMediaAction,
    required this.onClipboardCopy,
    required this.onConnectToPeer,
    required this.onSendCurrentClipboard,
    required this.onSendClipboardFile,
    required this.onDevicesTapped,
    this.onClearClipboardItem,
    this.onClearClipboardAll,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final primaryTools = <Widget>[
      ToolCard(
        title: 'Mirror Screen',
        subtitle: isPeerConnected
            ? 'View and control connected screen'
            : 'Connect a device first',
        icon: Icons.cast_connected_rounded,
        onTap: isPeerConnected ? onMirrorScreen : null,
      ),
      ToolCard(
        title: 'Mirror Keyboard',
        subtitle: 'Relay keystrokes to connected device',
        icon: Icons.keyboard_rounded,
        onTap: labsMirrorEnabled ? onMirrorKeyboard : null,
      ),
      ToolCard(
        title: 'Handoff URL',
        subtitle: 'Share browser links instantly',
        icon: Icons.open_in_new_rounded,
        onTap: onHandoffUrl,
      ),
      ToolCard(
        title: 'Student Hub',
        subtitle: 'Study links and citation workflow',
        icon: Icons.school_rounded,
        onTap: labsStudentHubEnabled ? onStudentHub : null,
      ),
    ];

    final advancedTools = <Widget>[
      if (!Platform.isMacOS)
        ToolCard(
          title: 'Remote Trackpad',
          subtitle: isPeerConnected
              ? 'Use device as Mac trackpad'
              : 'Connect to Mac first',
          icon: Icons.touch_app_rounded,
          onTap: isPeerConnected ? onTrackpad : null,
        ),
      if (Platform.isMacOS)
        ToolCard(
          title: 'Remote Camera',
          subtitle: !labsMirrorEnabled
              ? 'Enable Labs mirror features in Settings'
              : isPeerConnected
              ? 'View Android camera feed'
              : 'Connect a device first',
          icon: Icons.camera_alt_rounded,
          onTap: labsMirrorEnabled && isPeerConnected ? onRemoteCamera : null,
        ),
      if (Platform.isMacOS)
        ToolCard(
          title: 'Messages',
          subtitle: isPeerConnected ? 'View and send SMS' : 'Connect a device first',
          icon: Icons.chat_bubble_rounded,
          onTap: isPeerConnected ? onSms : null,
        ),
      if (Platform.isMacOS)
        ToolCard(
          title: 'Mount Phone in Finder',
          subtitle: 'Open Android files in Finder (WirePhone)',
          icon: Icons.usb_rounded,
          onTap: onMountPhoneInFinder,
        ),
      ToolCard(
        title: 'Find My Phone',
        subtitle: isPeerConnected
            ? 'Ring remotely at max volume'
            : 'Connect a device first',
        icon: Icons.ring_volume_rounded,
        onTap: isPeerConnected ? onFindPhone : null,
      ),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh ?? () async {},
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
            accent: scheme.primary,
            borderRadius: 24,
            elevated: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Text(
                          'CONTINUITY ENGINE',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Wire Control Center',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.35,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A unified workspace for sync, control, and advanced cross-device actions.',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.64),
                          fontSize: 13.5,
                          height: 1.32,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _TopStatChip(
                            icon: Icons.hub_rounded,
                            label: isPeerConnected ? 'Peer Linked' : 'No Peer',
                            color: isPeerConnected ? scheme.tertiary : scheme.outline,
                          ),
                          _TopStatChip(
                            icon: Icons.bolt_rounded,
                            label: isSyncing ? 'Sync Active' : 'Sync Idle',
                            color: isSyncing ? scheme.primary : scheme.outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.94),
                        scheme.secondary.withValues(alpha: 0.72),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: scheme.onPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          StatusDash(
            deviceName: deviceName,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            peerName: peerName,
            isPeerConnected: isPeerConnected,
            remoteBattery: remoteBattery,
            remoteIsCharging: remoteIsCharging,
            pingMs: pingMs,
            isSyncing: isSyncing,
          ),
          const SizedBox(height: 12),
          GlassCard(
            accent: scheme.secondary,
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: scheme.secondary.withValues(alpha: 0.14),
                  ),
                  child: Icon(Icons.health_and_safety_rounded, color: scheme.secondary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection Health: $connectionHealthLabel',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Last sync: $lastSyncLabel',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onReconnect,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Reconnect'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionHeader(title: 'Quick Actions'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickActionButton(
                icon: Icons.send_rounded,
                label: 'Sync Clipboard',
                onTap: onSendCurrentClipboard,
              ),
              _QuickActionButton(
                icon: Icons.devices_rounded,
                label: 'Devices',
                onTap: onDevicesTapped,
              ),
              _QuickActionButton(
                icon: Icons.file_upload_rounded,
                label: 'Paste File to Device',
                onTap: onSendClipboardFile,
              ),
              _QuickActionButton(
                icon: Icons.ring_volume_rounded,
                label: 'Find Phone',
                onTap: isPeerConnected ? onFindPhone : null,
              ),
              if (Platform.isMacOS)
                _QuickActionButton(
                  icon: Icons.usb_rounded,
                  label: 'Mount Finder',
                  onTap: onMountPhoneInFinder,
                ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Focus Mode',
            trailing: Switch(
              value: focusMode,
              onChanged: (_) => onToggleFocus(),
              activeThumbColor: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            accent: focusMode ? scheme.primary : scheme.outline,
            borderRadius: 20,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Deep Focus',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      focusMode ? Icons.bolt_rounded : Icons.timer_outlined,
                      color: focusMode
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  focusMode
                      ? 'Notifications and interruptions are minimized for concentrated work.'
                      : 'Enable focus mode to reduce interruptions and keep your flow state.',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.64),
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            accent: scheme.primary,
            elevated: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(title: 'Core Tools'),
                const SizedBox(height: 10),
                _ToolGrid(items: primaryTools),
                const SizedBox(height: 18),
                const _SectionHeader(title: 'Advanced Tools'),
                const SizedBox(height: 10),
                _ToolGrid(items: advancedTools),
              ],
            ),
          ),
          if (isPeerConnected) ...[
            const SizedBox(height: 12),
            MediaControlCard(
              onPlayPause: () => onMediaAction('media_play_pause'),
              onNext: () => onMediaAction('media_next'),
              onPrevious: () => onMediaAction('media_prev'),
              onVolumeUp: () => onMediaAction('media_vol_up'),
              onVolumeDown: () => onMediaAction('media_vol_down'),
              onMute: () => onMediaAction('media_vol_mute'),
            ),
          ],
          const SizedBox(height: 20),
          _SectionHeader(
            title: 'Recent Clipboard',
            trailing: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.secondary.withValues(alpha: 0.13),
                foregroundColor: scheme.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              onPressed: onClearClipboardAll,
            ),
          ),
          const SizedBox(height: 10),
          if (clipboardHistory.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No history yet',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.42)),
                ),
              ),
            )
          else
            ...clipboardHistory
                .take(3)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassCard(
                      accent: scheme.secondary,
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: scheme.secondary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.content_paste_rounded,
                              size: 16,
                              color: scheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.from,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface.withValues(alpha: 0.56),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: scheme.onSurface.withValues(alpha: 0.58),
                            ),
                            tooltip: 'Copy',
                            onPressed: () => onClipboardCopy(item.text),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: scheme.onSurface.withValues(alpha: 0.42),
                            ),
                            tooltip: 'Clear',
                            onPressed: onClearClipboardItem != null
                                ? () => onClearClipboardItem!(item)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: scheme.primary.withValues(alpha: 0.12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  final List<Widget> items;

  const _ToolGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1100
            ? 3
            : width >= 460
            ? 2
            : 1;
        final cardRatio = crossAxisCount == 3
            ? 2.2
            : crossAxisCount == 2
            ? (width >= 760 ? 2.25 : 1.95)
            : 2.4;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cardRatio,
          ),
          itemBuilder: (context, index) => StaggeredAnimatedItem(
            index: index,
            delay: 60,
            duration: const Duration(milliseconds: 450),
            child: items[index],
          ),
        );
      },
    );
  }
}

class _TopStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TopStatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.58),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.05,
          ),
        ),
        ?trailing,
      ],
    );
  }
}
