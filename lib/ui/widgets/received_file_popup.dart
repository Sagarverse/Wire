import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../../providers/app_state.dart';
import '../../services/file_transfer_service.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'glass_card.dart';

class ReceivedFilePopup extends StatefulWidget {
  final FileReceiveProgress progress;
  final VoidCallback onDismiss;

  const ReceivedFilePopup({
    super.key,
    required this.progress,
    required this.onDismiss,
  });

  @override
  State<ReceivedFilePopup> createState() => _ReceivedFilePopupState();
}

class _ReceivedFilePopupState extends State<ReceivedFilePopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _wiggleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _wiggleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 1.0, curve: Curves.easeInOut),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String ext) {
    ext = ext.toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['.mp4', '.mov', '.avi', '.mkv'].contains(ext)) {
      return Icons.video_library_rounded;
    }
    if (['.mp3', '.wav', '.flac', '.m4a'].contains(ext)) {
      return Icons.audiotrack_rounded;
    }
    if (['.pdf', '.doc', '.docx', '.txt'].contains(ext)) {
      return Icons.description_rounded;
    }
    if (['.zip', '.rar', '.7z', '.gz'].contains(ext)) {
      return Icons.archive_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = context.read<AppState>();
    final extension = p.extension(widget.progress.path);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.all(24),
          child: GlassCard(
            accent: scheme.onSurface,
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _getFileIcon(extension),
                        color: scheme.onSurface,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'File Received',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.progress.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _formatSize(widget.progress.total),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await _controller.reverse();
                        widget.onDismiss();
                      },
                      icon: const Icon(Icons.close_rounded),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          appState.openFileLocation(widget.progress.path);
                        },
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('Show in Folder'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Try to open the file directly
                          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
                            await Process.run('open', [widget.progress.path]);
                          } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
                            // On Android we'd use a plugin like open_file_safe
                            // For now fallback to folder
                            appState.openFileLocation(widget.progress.path);
                          }
                        },
                        icon: const Icon(Icons.launch_rounded, size: 18),
                        label: const Text('Open File'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: scheme.onSurface,
                          foregroundColor: scheme.surface,
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS ||
                    defaultTargetPlatform == TargetPlatform.windows ||
                    defaultTargetPlatform == TargetPlatform.linux)) ...[
                  const SizedBox(height: 16),
                  DragItemWidget(
                    dragItemProvider: (request) {
                      final item = DragItem(localData: widget.progress.path);
                      item.add(Formats.fileUri(Uri.file(widget.progress.path)));
                      return item;
                    },
                    allowedOperations: () => [DropOperation.copy],
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _wiggleAnimation,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _wiggleAnimation.value,
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 18,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Drag to copy to other apps',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
