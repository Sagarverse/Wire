import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../providers/remote_file_provider.dart';

class FileActionSheet extends StatelessWidget {
  final RemoteFileEntry entry;
  final RemoteFileProvider provider;

  const FileActionSheet({
    super.key,
    required this.entry,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(p.extension(entry.name).toLowerCase());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: isImage 
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        provider.getThumbnailUrl(entry),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: scheme.primary),
                      ),
                    )
                  : Icon(Icons.insert_drive_file_rounded, color: scheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.isDir ? 'Folder' : _formatSize(entry.size),
                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildActionItem(
            context,
            icon: Icons.download_rounded,
            label: 'Download to Mac',
            color: scheme.primary,
            onTap: () {
              provider.downloadFile(entry);
              Navigator.pop(context);
            },
          ),
          _buildActionItem(
            context,
            icon: Icons.open_in_new_rounded,
            label: 'Quick Preview',
            onTap: () {
              Navigator.pop(context);
              if (isImage) {
                _showPreviewDialog(context, scheme);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Preview only supported for images currently')),
                );
              }
            },
          ),
          _buildActionItem(
            context,
            icon: Icons.share_rounded,
            label: 'Share Link',
            onTap: () {
              Navigator.pop(context);
            },
          ),
          const Divider(height: 32),
          _buildActionItem(
            context,
            icon: Icons.delete_outline_rounded,
            label: 'Delete from Phone',
            color: scheme.error,
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Icon(icon, color: color ?? scheme.onSurface.withValues(alpha: 0.7), size: 22),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  color: color ?? scheme.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPreviewDialog(BuildContext context, ColorScheme scheme) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: InteractiveViewer(
                    child: Image.network(
                      provider.getThumbnailUrl(entry).replaceFirst('/thumb?', '/download?'), // Use full resolution if possible or handle in back
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 300,
                          height: 300,
                          color: scheme.surface,
                          child: Center(child: CircularProgressIndicator(value: loadingProgress.expectedTotalBytes != null ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null)),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              entry.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
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
}
