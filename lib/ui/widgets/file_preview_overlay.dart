import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../widgets/glass_card.dart';

class FilePreviewOverlay extends StatelessWidget {
  final String filePath;
  final String fileName;
  final int fileSize;
  final VoidCallback onOpen;
  final VoidCallback onShowInFolder;
  final VoidCallback onDismiss;

  const FilePreviewOverlay({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.onOpen,
    required this.onShowInFolder,
    required this.onDismiss,
  });

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes.toString().length - 1) ~/ 3;
    var res = bytes / (1024 * i);
    return "${res.toStringAsFixed(1)} ${suffixes[i]}";
  }

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _isImage(filePath);
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: GlassCard(
        blur: 20,
        opacity: 0.1,
        borderRadius: BorderRadius.circular(32),
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview Area
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: scheme.onSurface.withValues(alpha: 0.05),
                  child: isImage
                      ? Image.file(File(filePath), fit: BoxFit.cover)
                      : Icon(Icons.insert_drive_file_rounded, size: 64, color: scheme.primary.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 20),
              // File Info
              Text(
                fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatSize(fileSize),
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 24),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onOpen,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Open File', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onShowInFolder,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.1)),
                      ),
                      child: Text(
                        (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) ? 'Show in Finder' : 'Show in Folder',
                        style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onDismiss,
                child: Text('Dismiss', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
