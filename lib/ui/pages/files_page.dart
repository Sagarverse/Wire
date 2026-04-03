import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/transfer_item.dart';
import '../../providers/app_state.dart';
import '../../providers/file_transfer_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/staggered_animated_item.dart';
import '../../widgets/liquid_background.dart';
import 'remote_file_manager_page.dart';

class FilesPage extends StatelessWidget {
  final EdgeInsets? padding;
  const FilesPage({super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Consumer2<AppState, FileTransferProvider>(
      builder: (context, appState, provider, _) {
        final transfers = provider.transfers;
        final isPeerConnected = appState.pairingService.activeDevice != null;

        return LiquidBackground(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: (padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 24))
                      .add(const EdgeInsets.only(top: 40)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 50),
                      Text(
                        'FILE TRANSFERS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                          letterSpacing: 4.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Send & Receive',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                          letterSpacing: -1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Quick-Action Buttons ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Row(
                    children: [
                      // Send File
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.file_upload_rounded,
                          label: 'Send File',
                          accent: scheme.primary,
                          enabled: isPeerConnected,
                          onTap: () => _pickAndSendFile(context, appState),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Browse Remote
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.folder_shared_rounded,
                          label: 'Remote Files',
                          accent: Colors.indigo,
                          enabled: isPeerConnected,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RemoteFileManagerPage()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Open Downloads
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.folder_open_rounded,
                          label: 'Downloads',
                          accent: scheme.tertiary,
                          enabled: true,
                          onTap: () => _openDownloadsFolder(context, appState),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Mount / Unmount Finder Toggle (macOS only) ──
              if (Platform.isMacOS && isPeerConnected && appState.labsMountFinderEnabled)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: GlassCardInteractive(
                      onTap: () {
                        if (appState.isUsbMounted) {
                          appState.unmountAsUsb();
                        } else {
                          appState.mountAsUsb();
                        }
                      },
                      accent: appState.isUsbMounted ? Colors.green : scheme.secondary,
                      borderRadius: BorderRadius.circular(20),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (appState.isUsbMounted ? Colors.green : scheme.secondary)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              appState.isUsbMounted ? Icons.eject_rounded : Icons.usb_rounded,
                              color: appState.isUsbMounted ? Colors.green : scheme.secondary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appState.isUsbMounted ? 'Phone Mounted in Finder' : 'Mount Phone in Finder',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  appState.isUsbMounted
                                      ? 'Tap to safely eject'
                                      : 'Browse phone storage like a USB drive',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurface.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: (appState.isUsbMounted ? Colors.green : scheme.secondary)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              appState.isUsbMounted ? 'EJECT' : 'MOUNT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: appState.isUsbMounted ? Colors.green : scheme.secondary,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Transfer History Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                  child: Row(
                    children: [
                      Text(
                        'Recent Transfers',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (transfers.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _confirmClearHistory(context, provider),
                          icon: Icon(Icons.delete_sweep_rounded, size: 16, color: scheme.error.withValues(alpha: 0.7)),
                          label: Text(
                            'Clear',
                            style: TextStyle(color: scheme.error.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Transfer List ──
              if (transfers.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.swap_vert_rounded, size: 64, color: scheme.onSurface.withValues(alpha: 0.08)),
                          const SizedBox(height: 16),
                          Text(
                            'No transfers yet',
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3), fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPeerConnected ? 'Tap "Send File" to get started' : 'Connect a device first',
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.2), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = transfers[index];
                        return StaggeredAnimatedItem(
                          index: index,
                          child: _buildTransferTile(context, item, appState, scheme),
                        );
                      },
                      childCount: transfers.length,
                    ),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        );
      },
    );
  }

  // ── Pick a file and send it to the active peer ──
  void _pickAndSendFile(BuildContext context, AppState appState) async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sending ${result.files.single.name}...')),
        );
      }

      await appState.pushFile(filePath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent ${result.files.single.name} ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Open the local Downloads/Wire folder ──
  void _openDownloadsFolder(BuildContext context, AppState appState) async {
    try {
      if (Platform.isMacOS) {
        final path = appState.downloadsPath ?? '${Platform.environment['HOME']}/Downloads/Wire';
        await Process.run('open', [path]);
      } else if (Platform.isAndroid) {
        appState.openFileLocation('/storage/emulated/0/Download/Wire');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open folder: $e')),
        );
      }
    }
  }

  // ── Confirm then clear history ──
  void _confirmClearHistory(BuildContext context, FileTransferProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Clear Transfer History?'),
        content: const Text('This only removes the log — downloaded files are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              provider.clearHistory();
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferTile(BuildContext context, TransferItem item, AppState appState, ColorScheme scheme) {
    final isReceive = item.direction == 'receive';
    final isComplete = item.status == 'complete';
    final accent = isReceive ? scheme.primary : scheme.tertiary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCardInteractive(
        onTap: isComplete ? () => appState.openFileLocation(item.path) : null,
        accent: accent,
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isReceive ? Icons.file_download_rounded : Icons.file_upload_rounded,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (!isComplete) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        backgroundColor: accent.withValues(alpha: 0.1),
                        color: accent,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    isComplete
                        ? 'Tap to open location'
                        : '${(item.progress * 100).toInt()}% • ${_formatSize(item.total)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isComplete ? accent : scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            if (isComplete)
              Icon(Icons.check_circle_rounded, color: Colors.green.withValues(alpha: 0.5), size: 20)
            else
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── Reusable Action Button widget ──
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCardInteractive(
      onTap: enabled ? onTap : null,
      accent: enabled ? accent : null,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (enabled ? accent : scheme.onSurface).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: enabled ? accent : scheme.onSurface.withValues(alpha: 0.3), size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.3),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
