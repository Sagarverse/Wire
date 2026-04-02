import 'package:flutter/material.dart';
import '../../models/transfer_item.dart';
import '../widgets/glass_card.dart';

class FilesPage extends StatefulWidget {
  final List<TransferItem> transfers;
  final VoidCallback onClearHistory;
  final Function(TransferItem) onFileTap;
  final VoidCallback onSendFile;
  final VoidCallback onOpenDownloadsFolder;
  final VoidCallback? onOpenRemoteFiles; // null = no peer connected
  final Future<void> Function()? onRefresh;
  final Function(TransferItem)? onRetryTransfer;
  final Function(TransferItem)? onRemoveTransfer;

  const FilesPage({
    super.key,
    required this.transfers,
    required this.onClearHistory,
    required this.onFileTap,
    required this.onSendFile,
    required this.onOpenDownloadsFolder,
    this.onOpenRemoteFiles,
    this.onRefresh,
    this.onRetryTransfer,
    this.onRemoveTransfer,
  });

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeCount = widget.transfers
      .where((item) => item.status == 'sending' || item.status == 'receiving')
      .length;
    final failedCount = widget.transfers.where((item) => item.status == 'failed').length;
    final isSelectionMode = _selectedIds.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: GlassCard(
        borderRadius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        accent: scheme.primary,
        elevated: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isSelectionMode
                      ? '${_selectedIds.length} selected'
                      : 'Shared Files',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                if (isSelectionMode)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: scheme.onSurface),
                        tooltip: 'Clear selection',
                        onPressed: () => setState(() => _selectedIds.clear()),
                      ),
                      if (_selectedIds.any((id) => widget.transfers
                          .firstWhere((t) => t.id == id)
                          .status == 'failed') &&
                          widget.onRetryTransfer != null)
                        IconButton(
                          icon: Icon(Icons.refresh_rounded, color: scheme.primary),
                          tooltip: 'Retry selected',
                          onPressed: _retrySelected,
                        ),
                      IconButton(
                        icon: Icon(Icons.delete_rounded, color: scheme.error),
                        tooltip: 'Remove selected',
                        onPressed: _removeSelected,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      GlassCard(
                        accent: scheme.secondary,
                        padding: EdgeInsets.zero,
                        child: InkWell(
                          onTap: widget.onOpenRemoteFiles,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_shared_rounded,
                                  size: 16,
                                  color: widget.onOpenRemoteFiles != null
                                      ? scheme.secondary
                                      : scheme.onSurface.withValues(alpha: 0.25),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Remote Files',
                                  style: TextStyle(
                                    color: widget.onOpenRemoteFiles != null
                                        ? scheme.onSurface
                                        : scheme.onSurface.withValues(alpha: 0.28),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ActionIcon(
                        tooltip: 'Open local folder',
                        icon: Icons.folder_open_rounded,
                        onPressed: widget.onOpenDownloadsFolder,
                      ),
                      _ActionIcon(
                        tooltip: 'Send file',
                        icon: Icons.upload_file_rounded,
                        onPressed: widget.onSendFile,
                      ),
                      if (widget.transfers.isNotEmpty)
                        _ActionIcon(
                          tooltip: 'Clear history',
                          icon: Icons.delete_sweep_rounded,
                          onPressed: widget.onClearHistory,
                        ),
                    ],
                  ),
              ],
            ),
            // ... rest of the children ...
            if (!isSelectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                child: Row(
                  children: [
                    _QueueChip(
                      icon: Icons.wifi_protected_setup_rounded,
                      label: '$activeCount active',
                      color: activeCount > 0 ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    _QueueChip(
                      icon: Icons.error_outline_rounded,
                      label: '$failedCount failed',
                      color: failedCount > 0 ? scheme.error : scheme.outline,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.onRefresh ?? () async {},
                child: widget.transfers.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: 320,
                            child: Center(
                              child: Text(
                                'No shared files yet',
                                style: TextStyle(
                                  color: scheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: widget.transfers.length,
                        itemBuilder: (context, index) {
                          final item = widget.transfers[index];
                          final isSelected = _selectedIds.contains(item.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassCard(
                              accent: isSelected 
                                  ? scheme.primary 
                                  : _getStatusColor(item.status),
                              padding: const EdgeInsets.all(15),
                              child: ListTile(
                                onTap: isSelectionMode
                                    ? () => _toggleSelection(item.id)
                                    : () => widget.onFileTap(item),
                                onLongPress: () => _toggleSelection(item.id),
                                contentPadding: EdgeInsets.zero,
                                leading: isSelectionMode
                                    ? Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => _toggleSelection(item.id),
                                      )
                                    : Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(item.status).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _getStatusIcon(item.status),
                                          color: _getStatusColor(item.status),
                                        ),
                                      ),
                                title: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      item.status.toUpperCase(),
                                      style: TextStyle(
                                        color: _getStatusColor(item.status),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (item.status == 'receiving' ||
                                        item.status == 'sending') ...[
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: LinearProgressIndicator(
                                          value: item.progress,
                                          backgroundColor:
                                              scheme.onSurface.withValues(alpha: 0.12),
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            _getStatusColor(item.status),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${(item.progress * 100).toInt()}%',
                                              style: TextStyle(
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.7),
                                                fontSize: 11,
                                              ),
                                            ),
                                            Text(
                                              '${item.speedLabel} • ETA: ${item.etaLabel}',
                                              style: TextStyle(
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.6),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: item.status == 'complete'
                                    ? Icon(
                                        Icons.open_in_new_rounded,
                                        color: scheme.onSurface.withValues(alpha: 0.52),
                                        size: 20,
                                      )
                                    : _buildTransferActions(context, item),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _retrySelected() {
    final toRetry = widget.transfers
        .where((t) => _selectedIds.contains(t.id) && t.status == 'failed')
        .toList();
    for (final item in toRetry) {
      widget.onRetryTransfer?.call(item);
    }
    setState(() => _selectedIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Retrying ${toRetry.length} transfer(s)...')),
    );
  }

  void _removeSelected() {
    final toRemove = widget.transfers
        .where((t) => _selectedIds.contains(t.id))
        .toList();
    final removedIds = List<String>.from(_selectedIds);
    
    for (final item in toRemove) {
      widget.onRemoveTransfer?.call(item);
    }
    setState(() => _selectedIds.clear());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${toRemove.length} transfer(s)'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            for (final id in removedIds) {
              final item = toRemove.firstWhere((t) => t.id == id);
              widget.transfers.add(item);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Undo successful')),
            );
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'complete':
        return Icons.insert_drive_file;
      case 'receiving':
        return Icons.download_for_offline;
      case 'sending':
        return Icons.upload_file;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'complete':
        return Colors.greenAccent;
      case 'receiving':
        return Colors.blueAccent;
      case 'sending':
        return Colors.orangeAccent;
      case 'failed':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  Widget? _buildTransferActions(BuildContext context, TransferItem item) {
    final scheme = Theme.of(context).colorScheme;

    if (item.status == 'failed' && widget.onRetryTransfer != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Retry',
            onPressed: () => widget.onRetryTransfer!(item),
            icon: Icon(Icons.restart_alt_rounded, color: scheme.primary, size: 20),
          ),
          if (widget.onRemoveTransfer != null)
            IconButton(
              tooltip: 'Remove',
              onPressed: () => widget.onRemoveTransfer!(item),
              icon: Icon(
                Icons.close_rounded,
                color: scheme.onSurface.withValues(alpha: 0.6),
                size: 20,
              ),
            ),
        ],
      );
    }

    if ((item.status == 'sending' || item.status == 'receiving') && widget.onRemoveTransfer != null) {
      return IconButton(
        tooltip: 'Remove from queue',
        onPressed: () => widget.onRemoveTransfer!(item),
        icon: Icon(
          Icons.cancel_outlined,
          color: scheme.onSurface.withValues(alpha: 0.6),
          size: 20,
        ),
      );
    }

    return null;
  }
}

class _QueueChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QueueChip({
    required this.icon,
    required this.label,
    required this.color,
  });

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

class _ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
        ),
        child: IconButton(
          icon: Icon(icon, color: scheme.onSurface.withValues(alpha: 0.75)),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
