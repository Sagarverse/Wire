import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/app_state.dart';
import '../../services/file_transfer_service.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class ReceivedFilePopup extends StatelessWidget {
  final FileReceiveProgress progress;
  final VoidCallback onDismiss;
  final bool isStandalone;
  final String? senderName;

  const ReceivedFilePopup({
    super.key,
    required this.progress,
    required this.onDismiss,
    this.isStandalone = false,
    this.senderName,
  });

  bool _isImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
  }

  bool _isVideo(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.webm'].contains(ext);
  }

  IconData _fileIcon(String path) {
    final ext = p.extension(path).toLowerCase();
    if (_isImage(path)) return Icons.image_rounded;
    if (_isVideo(path)) return Icons.videocam_rounded;
    if (['.pdf'].contains(ext)) return Icons.picture_as_pdf_rounded;
    if (['.doc', '.docx', '.txt', '.rtf'].contains(ext)) return Icons.description_rounded;
    if (['.zip', '.rar', '.7z', '.tar', '.gz'].contains(ext)) return Icons.folder_zip_rounded;
    if (['.mp3', '.wav', '.flac', '.aac', '.ogg'].contains(ext)) return Icons.audiotrack_rounded;
    if (['.apk', '.ipa'].contains(ext)) return Icons.android_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Resolve sender name: use provider if available, else use passed-in name
    String sender;
    if (isStandalone) {
      sender = senderName ?? 'Nearby Device';
    } else {
      try {
        final appState = context.read<AppState>();
        sender = appState.pairingService.activeDevice?.name ?? 'Nearby Device';
      } catch (_) {
        sender = senderName ?? 'Nearby Device';
      }
    }

    final containerColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F1EC);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 60,
                offset: const Offset(0, 24),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Preview Area (Draggable) ──
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                child: DragItemWidget(
                  dragItemProvider: (request) {
                    final item = DragItem(localData: progress.path);
                    item.add(Formats.fileUri(Uri.file(progress.path)));
                    return item;
                  },
                  allowedOperations: () => [DropOperation.copy],
                  child: Container(
                    width: double.infinity,
                    height: 220,
                    color: isDark ? const Color(0xFF111111) : const Color(0xFFF5F5F5),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Image preview or file icon
                        if (_isImage(progress.path))
                          Image.file(
                            File(progress.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildFileIconPreview(scheme, isDark),
                          )
                        else
                          _buildFileIconPreview(scheme, isDark),

                        // Draggable hint overlay
                        if (Platform.isMacOS)
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.drag_indicator_rounded, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'DRAG TO EXTRACT',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Dismiss button
                        Positioned(
                          top: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: onDismiss,
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── 2. Success Badge ──
              Transform.translate(
                offset: const Offset(0, -22),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    shape: BoxShape.circle,
                    border: Border.all(color: containerColor, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF34C759).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
                ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
              ),

              // ── 3. File Info ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Column(
                  children: [
                    // Filename pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.onSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        progress.name,
                        style: TextStyle(
                          color: scheme.surface,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 8),
                    Text(
                      'Received from $sender',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                    const SizedBox(height: 4),
                    Text(
                      _formatBytes(progress.total),
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.25),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ).animate().fadeIn(delay: 350.ms),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── 4. Action Buttons ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: Platform.isMacOS ? 'Show in Finder' : 'Open Folder',
                        color: scheme.onSurface.withValues(alpha: 0.06),
                        textColor: scheme.onSurface,
                        onTap: () {
                          if (isStandalone) {
                            if (Platform.isMacOS) {
                              Process.run('open', ['-R', progress.path]);
                            }
                          } else {
                            context.read<AppState>().openFileLocation(progress.path);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        label: 'Open',
                        color: const Color(0xFF111111),
                        textColor: Colors.white,
                        onTap: () async {
                          if (Platform.isMacOS) {
                            await Process.run('open', [progress.path]);
                          } else {
                            if (!isStandalone) {
                              context.read<AppState>().openFileLocation(progress.path);
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: _ActionButton(
                    label: 'Delete',
                    color: Colors.redAccent.withValues(alpha: 0.08),
                    textColor: Colors.redAccent,
                    onTap: () => _showDeleteConfirmation(context),
                  ),
                ),
              ),

              // macOS drag-to-copy
              if (!kIsWeb && Platform.isMacOS) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: DragItemWidget(
                    dragItemProvider: (request) {
                      final item = DragItem(localData: progress.path);
                      item.add(Formats.fileUri(Uri.file(progress.path)));
                      return item;
                    },
                    allowedOperations: () => [DropOperation.copy],
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.05),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.drag_indicator_rounded, size: 14, color: scheme.onSurface.withValues(alpha: 0.3)),
                          const SizedBox(width: 6),
                          Text(
                            'Drag to copy',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack);
  }

  Widget _buildFileIconPreview(ColorScheme scheme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _fileIcon(progress.path),
            size: 48,
            color: scheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          p.extension(progress.path).toUpperCase().replaceFirst('.', ''),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: scheme.onSurface.withValues(alpha: 0.2),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete File?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        content: Text(
          'This will permanently remove "${progress.name}" from your device.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteFile(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(BuildContext context) async {
    try {
      final appState = context.read<AppState>();
      await appState.deleteReceivedFile(progress.path);
    } catch (_) {
      try {
        final file = File(progress.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    onDismiss();
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
