import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../controllers/clipboard_controller.dart';
import '../../providers/app_state.dart';
import '../../providers/file_transfer_provider.dart';
import '../../widgets/liquid_background.dart';
import '../../widgets/wire_logo.dart';
import 'device_pairing_page.dart';
import 'remote_file_manager_page.dart';

class ControlHubPage extends StatelessWidget {
  final EdgeInsets? padding;

  const ControlHubPage({super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    return Consumer3<AppState, ClipboardController, FileTransferProvider>(
      builder: (context, appState, clipboardController, fileTransferProvider, _) {
        final active = appState.pairingService.activeDevice;
        final isConnected = appState.connectionStatus == ConnectionStatus.connected ||
            appState.connectionStatus == ConnectionStatus.syncing;
        final isConnecting = appState.connectionStatus == ConnectionStatus.connecting;
        final scheme = Theme.of(context).colorScheme;

        return LiquidBackground(
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                HapticFeedback.mediumImpact();
                if (active != null) appState.reconnect();
                await Future.delayed(const Duration(milliseconds: 600));
              },
              color: scheme.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: padding ??
                        EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 100),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Wire Title ──
                          Row(
                            children: [
                              const WireLogo(size: 32, showGlow: true),
                              const SizedBox(width: 10),
                              Text(
                                'Wire',
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                            ],
                          ).animate().fadeIn(duration: 400.ms),
                          const SizedBox(height: 16),

                          // ── Device Card ──
                          _DeviceCard(
                            deviceName: active?.name,
                            isConnected: isConnected,
                            isConnecting: isConnecting,
                            batteryLevel: active?.batteryLevel,
                            isCharging: active?.isCharging ?? false,
                            connectionType: appState.connectionType,
                            onPair: () => _openPairing(context, appState),
                            onReconnect: active == null ? null : appState.reconnect,
                          ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.04, end: 0),

                          const SizedBox(height: 20),

                          // ── Send & Receive Buttons (ShareIt style) ──
                          Row(
                            children: [
                              Expanded(
                                child: _BigActionButton(
                                  icon: Icons.upload_rounded,
                                  label: 'Send',
                                  subtitle: 'Share files',
                                  color: scheme.primary,
                                  onTap: active == null
                                      ? null
                                      : () => _pickAndSend(context, appState),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _BigActionButton(
                                  icon: Icons.download_rounded,
                                  label: 'Receive',
                                  subtitle: 'Ready to receive',
                                  color: const Color(0xFF34C759),
                                  onTap: active == null ? null : () {},
                                ),
                              ),
                            ],
                          ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.04, end: 0),

                          const SizedBox(height: 24),

                          // ── Features (KDE Connect style) ──
                          _SectionTitle(title: 'Features'),
                          const SizedBox(height: 12),

                          // Feature grid — 2 columns
                          _FeaturesGrid(
                            isConnected: isConnected,
                            clipboardPaused: clipboardController.isSyncPaused,
                            notificationSync: appState.notificationSyncEnabled,
                            onClipboardToggle: () =>
                                clipboardController.setSyncPaused(!clipboardController.isSyncPaused),
                            onNotificationToggle: () => appState.toggleSetting(
                                'notification_sync_enabled', !appState.notificationSyncEnabled),
                            onRemoteFiles: active == null
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const RemoteFileManagerPage()),
                                    ),
                            onRingDevice: active == null ? null : appState.findPhone,
                            onMount: (!kIsWeb &&
                                    defaultTargetPlatform == TargetPlatform.macOS &&
                                    active != null)
                                ? () => appState.isUsbMounted
                                    ? appState.unmountAsUsb()
                                    : appState.mountAsUsb()
                                : null,
                            usbMounted: appState.isUsbMounted,
                          ).animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.03, end: 0),

                          const SizedBox(height: 24),

                          // ── Active Transfers ──
                          if (fileTransferProvider.transfers.any(
                              (t) => t.status == 'sending' || t.status == 'receiving')) ...[
                            _SectionTitle(title: 'Transfers'),
                            const SizedBox(height: 12),
                            ...fileTransferProvider.transfers
                                .where((t) => t.status == 'sending' || t.status == 'receiving')
                                .map((item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _TransferCard(item: item),
                                    )),
                            const SizedBox(height: 12),
                          ],

                          // ── Recent Activity (compact) ──
                          if (appState.recentTransfers.isNotEmpty) ...[
                            _SectionTitle(title: 'Recent'),
                            const SizedBox(height: 10),
                            ...appState.recentTransfers.take(3).map((item) => _RecentRow(
                                  name: item.name,
                                  subtitle: _formatSize(item.size),
                                  onTap: () => appState.openFileLocation(item.path),
                                )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPairing(BuildContext context, AppState appState) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DevicePairingPage(
          pairingService: appState.pairingService,
          discoveredPeers: appState.discoveredPeers,
          localDeviceId: appState.deviceId,
          onMakeActive: (device) => appState.connectToPeer(
            device.lastIp,
            targetId: device.deviceId,
            targetName: device.name,
          ),
          onConnectToPeer: (peer) => appState.connectToPeer(
            peer.addresses.isNotEmpty ? peer.addresses : peer.address,
            targetId: peer.deviceId,
            targetName: peer.deviceName,
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSend(BuildContext context, AppState appState) async {
    final transferProvider = context.read<FileTransferProvider>();
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final paths = result.paths.whereType<String>().toList();
    if (paths.isEmpty) return;
    try {
      await appState.pushFiles(paths, provider: transferProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sending ${paths.length} file${paths.length == 1 ? '' : 's'}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $error')),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ─── Device Card (KDE Connect inspired) ────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final String? deviceName;
  final bool isConnected;
  final bool isConnecting;
  final int? batteryLevel;
  final bool isCharging;
  final String connectionType;
  final VoidCallback onPair;
  final VoidCallback? onReconnect;

  const _DeviceCard({
    required this.deviceName,
    required this.isConnected,
    required this.isConnecting,
    required this.batteryLevel,
    required this.isCharging,
    required this.connectionType,
    required this.onPair,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isConnected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        scheme.primary.withValues(alpha: 0.15),
                        scheme.primary.withValues(alpha: 0.05),
                      ]
                    : [
                        scheme.primary.withValues(alpha: 0.08),
                        scheme.primary.withValues(alpha: 0.02),
                      ],
              )
            : null,
        color: isConnected ? null : scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isConnected
              ? scheme.primary.withValues(alpha: 0.2)
              : scheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: deviceName == null
          ? _buildUnpairedState(context, scheme)
          : _buildPairedState(context, scheme),
    );
  }

  Widget _buildUnpairedState(BuildContext context, ColorScheme scheme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.devices_rounded, size: 32, color: scheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          'No device connected',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Scan a QR code to pair your phone and computer',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onPair,
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Pair device'),
        ),
      ],
    );
  }

  Widget _buildPairedState(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        // Device avatar
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.phone_android_rounded, size: 26, color: scheme.primary),
        ),
        const SizedBox(width: 16),
        // Device info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      deviceName!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(isConnected: isConnected, isConnecting: isConnecting),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (isConnected && batteryLevel != null) ...[
                    Icon(
                      isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                      size: 14,
                      color: batteryLevel! <= 20
                          ? Colors.redAccent
                          : scheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$batteryLevel%',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (isConnected && connectionType.isNotEmpty)
                    Text(
                      connectionType,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  if (!isConnected)
                    Text(
                      'Tap to reconnect',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Actions
        if (!isConnected && onReconnect != null)
          IconButton(
            onPressed: onReconnect,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              foregroundColor: scheme.primary,
              backgroundColor: scheme.primary.withValues(alpha: 0.08),
            ),
          ),
        IconButton(
          onPressed: onPair,
          icon: const Icon(Icons.settings_outlined, size: 20),
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

// ─── Status Pill ───────────────────────────────────────────────────────────────

class _StatusPill extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;

  const _StatusPill({required this.isConnected, required this.isConnecting});

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isConnected) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusPill old) {
    super.didUpdateWidget(old);
    if (widget.isConnected && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isConnected && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnected
        ? const Color(0xFF34C759)
        : widget.isConnecting
            ? const Color(0xFFFF9F0A)
            : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, _) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: widget.isConnected
                    ? [BoxShadow(color: color.withValues(alpha: 0.3 + _pulseCtrl.value * 0.3), blurRadius: 4)]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            widget.isConnected
                ? 'Connected'
                : widget.isConnecting
                    ? 'Connecting'
                    : 'Offline',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Big Action Button (ShareIt style) ─────────────────────────────────────────

class _BigActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _BigActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.mediumImpact();
                  onTap!();
                }
              : null,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28),
      ),
    );
  }
}

// ─── Features Grid (KDE Connect style) ─────────────────────────────────────────

class _FeaturesGrid extends StatelessWidget {
  final bool isConnected;
  final bool clipboardPaused;
  final bool notificationSync;
  final VoidCallback onClipboardToggle;
  final VoidCallback onNotificationToggle;
  final VoidCallback? onRemoteFiles;
  final VoidCallback? onRingDevice;
  final VoidCallback? onMount;
  final bool usbMounted;

  const _FeaturesGrid({
    required this.isConnected,
    required this.clipboardPaused,
    required this.notificationSync,
    required this.onClipboardToggle,
    required this.onNotificationToggle,
    required this.onRemoteFiles,
    required this.onRingDevice,
    this.onMount,
    required this.usbMounted,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 10.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: tileWidth,
              child: _FeatureTile(
                icon: clipboardPaused ? Icons.content_paste_off_rounded : Icons.content_paste_go_rounded,
                title: 'Clipboard',
                subtitle: clipboardPaused ? 'Paused' : 'Syncing',
                isActive: !clipboardPaused,
                onTap: onClipboardToggle,
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _FeatureTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: notificationSync ? 'Mirroring' : 'Off',
                isActive: notificationSync,
                onTap: onNotificationToggle,
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _FeatureTile(
                icon: Icons.folder_outlined,
                title: 'Remote Files',
                subtitle: 'Browse device',
                isActive: false,
                onTap: onRemoteFiles,
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _FeatureTile(
                icon: Icons.ring_volume_outlined,
                title: 'Find Device',
                subtitle: 'Ring phone',
                isActive: false,
                onTap: onRingDevice,
              ),
            ),
            if (onMount != null)
              SizedBox(
                width: tileWidth,
                child: _FeatureTile(
                  icon: usbMounted ? Icons.usb_off_rounded : Icons.usb_rounded,
                  title: usbMounted ? 'Unmount' : 'Mount',
                  subtitle: 'Finder access',
                  isActive: usbMounted,
                  onTap: onMount,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback? onTap;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap!();
                }
              : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive
                  ? scheme.primary.withValues(alpha: 0.08)
                  : scheme.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isActive
                    ? scheme.primary.withValues(alpha: 0.2)
                    : scheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? scheme.primary : scheme.onSurface.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isActive ? scheme.primary : scheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Transfer Card ─────────────────────────────────────────────────────────────

class _TransferCard extends StatelessWidget {
  final dynamic item;
  const _TransferCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (item.progress as double).clamp(0.0, 1.0);
    final isSending = item.direction == 'send';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Circular progress
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: scheme.primary.withValues(alpha: 0.1),
                  color: scheme.primary,
                ),
                Icon(
                  isSending ? Icons.upload_rounded : Icons.download_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name as String,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toInt()}% · ${isSending ? 'Sending' : 'Receiving'}',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Row ────────────────────────────────────────────────────────────────

class _RecentRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final VoidCallback onTap;

  const _RecentRow({
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.insert_drive_file_outlined, size: 18, color: scheme.onSurface.withValues(alpha: 0.35)),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: subtitle.isNotEmpty
            ? Text(subtitle, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.35), fontSize: 11))
            : null,
        trailing: Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurface.withValues(alpha: 0.15)),
      ),
    );
  }
}
