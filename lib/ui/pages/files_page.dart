import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../providers/file_transfer_provider.dart';
import '../../widgets/liquid_background.dart';
import 'remote_file_manager_page.dart';

class FilesPage extends StatelessWidget {
  final EdgeInsets? padding;
  const FilesPage({super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, FileTransferProvider>(
      builder: (context, appState, transferProvider, _) {
        final scheme = Theme.of(context).colorScheme;
        final active = appState.pairingService.activeDevice;
        final isConnected = appState.connectionStatus == ConnectionStatus.connected ||
            appState.connectionStatus == ConnectionStatus.syncing;

        return LiquidBackground(
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Files', style: Theme.of(context).textTheme.headlineMedium)
                            .animate().fadeIn(duration: 400.ms).slideX(begin: -0.05, end: 0),
                        const SizedBox(height: 4),
                        Text(
                          isConnected
                              ? 'Send and receive files with ${active?.name ?? 'your device'}'
                              : 'Connect a device to start sharing files',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Send files card
                        _SendFilesCard(
                          isConnected: isConnected,
                          onSend: isConnected ? () => _pickAndSend(context, appState) : null,
                          onRemoteBrowse: isConnected
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const RemoteFileManagerPage()),
                                  )
                              : null,
                        ),
                        const SizedBox(height: 20),
                        // Active transfers
                        if (transferProvider.transfers.any((t) =>
                            t.status == 'sending' || t.status == 'receiving')) ...[
                          _SectionHeader(
                            title: 'Active transfers',
                            icon: Icons.sync_rounded,
                          ),
                          const SizedBox(height: 12),
                          ...transferProvider.transfers
                              .where((t) => t.status == 'sending' || t.status == 'receiving')
                              .map((item) => _ActiveTransferTile(item: item)),
                          const SizedBox(height: 20),
                        ],
                        // Transfer history
                        _SectionHeader(
                          title: 'Transfer history',
                          icon: Icons.history_rounded,
                          trailing: transferProvider.transfers.isNotEmpty
                              ? TextButton(
                                  onPressed: () => _showClearDialog(context, transferProvider),
                                  child: Text(
                                    'Clear',
                                    style: TextStyle(
                                      color: scheme.onSurface.withValues(alpha: 0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                // Transfer history list
                _buildHistoryList(context, appState, transferProvider, scheme),
                // Bottom padding
                SliverPadding(
                  padding: padding ?? EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 100),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList(
    BuildContext context,
    AppState appState,
    FileTransferProvider transferProvider,
    ColorScheme scheme,
  ) {
    final completedTransfers = transferProvider.transfers
        .where((t) => t.status == 'complete' || t.status == 'failed')
        .toList();

    final recentTransfers = appState.recentTransfers;

    final allItems = <_TransferDisplayItem>[];
    for (final t in completedTransfers) {
      allItems.add(_TransferDisplayItem(
        name: t.name,
        path: t.path,
        status: t.status,
        direction: t.direction,
        size: t.total,
        time: t.startTime,
      ));
    }
    for (final t in recentTransfers) {
      if (!allItems.any((i) => i.path == t.path)) {
        allItems.add(_TransferDisplayItem(
          name: t.name,
          path: t.path,
          status: 'complete',
          direction: 'receive',
          size: t.size,
          time: t.timestamp,
        ));
      }
    }

    if (allItems.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 40,
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 12),
                Text(
                  'No transfers yet',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.35),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Send or receive files to see them here',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.25),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.builder(
        itemCount: allItems.length,
        itemBuilder: (context, index) {
          final item = allItems[index];
          return _TransferHistoryTile(
            item: item,
            onOpen: () => appState.openFileLocation(item.path),
          );
        },
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
          SnackBar(content: Text('Sending ${paths.length} item${paths.length == 1 ? '' : 's'}')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $error')),
        );
      }
    }
  }

  void _showClearDialog(BuildContext context, FileTransferProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear transfer history?'),
        content: const Text('This removes completed and failed transfers from the list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              provider.clearHistory();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _SendFilesCard extends StatelessWidget {
  final bool isConnected;
  final VoidCallback? onSend;
  final VoidCallback? onRemoteBrowse;

  const _SendFilesCard({
    required this.isConnected,
    this.onSend,
    this.onRemoteBrowse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.upload_file_rounded,
                  label: 'Send files',
                  subtitle: 'Pick & share',
                  onTap: onSend,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.folder_outlined,
                  label: 'Remote files',
                  subtitle: 'Browse device',
                  onTap: onRemoteBrowse,
                ),
              ),
            ],
          ),
          if (!isConnected) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.35)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connect a device to enable file sharing',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
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

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(height: 10),
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 11,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurface.withValues(alpha: 0.35)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class _ActiveTransferTile extends StatelessWidget {
  final dynamic item;
  const _ActiveTransferTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (item.progress as double).clamp(0.0, 1.0);
    final isSending = item.direction == 'send';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSending ? Icons.upload_rounded : Icons.download_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name as String,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: scheme.primary.withValues(alpha: 0.1),
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferHistoryTile extends StatelessWidget {
  final _TransferDisplayItem item;
  final VoidCallback onOpen;

  const _TransferHistoryTile({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isReceived = item.direction == 'receive';
    final isFailed = item.status == 'failed';
    final ext = item.name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                // File preview / icon
                if (isImage && item.path.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: Image.asset(
                        item.path,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _FileIcon(
                          ext: ext,
                          isFailed: isFailed,
                          isReceived: isReceived,
                        ),
                      ),
                    ),
                  )
                else
                  _FileIcon(ext: ext, isFailed: isFailed, isReceived: isReceived),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatSize(item.size)} · ${isReceived ? 'Received' : 'Sent'}${item.time != null ? ' · ${_formatTimeAgo(item.time!)}' : ''}',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}';
  }
}

class _FileIcon extends StatelessWidget {
  final String ext;
  final bool isFailed;
  final bool isReceived;

  const _FileIcon({required this.ext, required this.isFailed, required this.isReceived});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isFailed ? Colors.redAccent : _colorForExt(ext, scheme);
    final icon = isFailed ? Icons.error_outline_rounded : _iconForExt(ext, isReceived);

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  static IconData _iconForExt(String ext, bool isReceived) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return Icons.image_rounded;
      case 'mp4': case 'mov': case 'avi': case 'mkv':
        return Icons.videocam_rounded;
      case 'mp3': case 'aac': case 'flac': case 'wav':
        return Icons.music_note_rounded;
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return Icons.folder_zip_rounded;
      case 'apk': return Icons.android_rounded;
      case 'doc': case 'docx': return Icons.description_rounded;
      case 'xls': case 'xlsx': return Icons.table_chart_rounded;
      default:
        return isReceived ? Icons.download_done_rounded : Icons.upload_rounded;
    }
  }

  static Color _colorForExt(String ext, ColorScheme scheme) {
    switch (ext) {
      case 'pdf': return const Color(0xFFEF4444);
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return const Color(0xFFF59E0B);
      case 'mp4': case 'mov': case 'avi': case 'mkv':
        return const Color(0xFF8B5CF6);
      case 'mp3': case 'aac': case 'flac': case 'wav':
        return const Color(0xFFEC4899);
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return const Color(0xFF78716C);
      case 'apk': return const Color(0xFF34D399);
      default: return scheme.primary;
    }
  }
}

class _TransferDisplayItem {
  final String name;
  final String path;
  final String status;
  final String direction;
  final int size;
  final DateTime? time;

  const _TransferDisplayItem({
    required this.name,
    required this.path,
    required this.status,
    required this.direction,
    required this.size,
    this.time,
  });
}
