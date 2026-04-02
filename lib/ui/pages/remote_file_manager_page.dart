import 'dart:math';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/file_transfer_service.dart';
import '../widgets/glass_card.dart';
import 'file_preview_page.dart';

class RemoteFileEntry {
  RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.modified,
  });

  factory RemoteFileEntry.fromJson(Map<String, dynamic> json) {
    return RemoteFileEntry(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      isDir: json['isDir'] == true,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int modified;
}

class RemoteFileManagerPage extends StatefulWidget {
  final String peerHost;
  final int filePort;
  final FileTransferService fileTransferService;
  final void Function(String filePath) onSendFile;

  const RemoteFileManagerPage({
    super.key,
    required this.peerHost,
    required this.filePort,
    required this.fileTransferService,
    required this.onSendFile,
  });

  @override
  State<RemoteFileManagerPage> createState() => _RemoteFileManagerPageState();
}

class _RemoteFileManagerPageState extends State<RemoteFileManagerPage> {
  final List<String> _pathStack = [];
  String? _currentPath;
  String? _parentPath;
  List<RemoteFileEntry> _entries = [];
  bool _loading = false;
  String? _error;
  bool _dragActive = false;

  // Download tracking: remotePath -> progress (0.0–1.0, or -1 for error, 2.0 for done)
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _browse(null);
  }

  Future<void> _browse(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.fileTransferService.browseRemote(
        host: widget.peerHost,
        port: widget.filePort,
        path: path,
      );
      final entries = (result['entries'] as List<dynamic>? ?? [])
          .map((e) => RemoteFileEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _currentPath = result['currentPath']?.toString();
        _parentPath = result['parentPath']?.toString();
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _downloadFile(RemoteFileEntry entry) async {
    setState(() {
      _downloadProgress[entry.path] = 0.0;
    });
    try {
      await widget.fileTransferService.downloadRemoteFile(
        host: widget.peerHost,
        port: widget.filePort,
        remotePath: entry.path,
        filename: entry.name,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgress[entry.path] = received / total;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _downloadProgress[entry.path] = 2.0; // Done sentinel
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: ${entry.name}'),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
          ),
        );
        // Clear after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _downloadProgress.remove(entry.path));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress[entry.path] = -1.0; // Error sentinel
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _downloadProgress.remove(entry.path));
        });
      }
    }
  }

  Future<void> _previewFile(RemoteFileEntry entry) async {
    setState(() {
      _downloadProgress[entry.path] = 0.0;
    });

    try {
      final localPath = await widget.fileTransferService
          .downloadRemoteFileToTemp(
            host: widget.peerHost,
            port: widget.filePort,
            remotePath: entry.path,
            filename: entry.name,
            onProgress: (received, total) {
              if (total > 0 && mounted) {
                setState(() {
                  _downloadProgress[entry.path] = received / total;
                });
              }
            },
          );

      if (mounted) {
        setState(() {
          _downloadProgress.remove(entry.path);
        });
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FilePreviewPage(filePath: localPath),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress[entry.path] = -1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preview failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _downloadProgress.remove(entry.path));
        });
      }
    }
  }

  void _navigateInto(RemoteFileEntry entry) {
    if (entry.isDir) {
      if (_currentPath != null) _pathStack.add(_currentPath!);
      _browse(entry.path);
    }
  }

  void _navigateUp() {
    if (_parentPath != null) {
      if (_pathStack.isNotEmpty) _pathStack.removeLast();
      _browse(_parentPath);
    } else if (_pathStack.isNotEmpty) {
      final prev = _pathStack.removeLast();
      _browse(prev);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canGoUp = _parentPath != null || _pathStack.isNotEmpty;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragActive = true),
      onDragExited: (_) => setState(() => _dragActive = false),
      onDragDone: (details) {
        setState(() => _dragActive = false);
        for (final file in details.files) {
          widget.onSendFile(file.path);
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: scheme.primary.withValues(alpha: 0.85),
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: scheme.onPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.folder_open,
                    color: scheme.onPrimary.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentPath != null
                          ? p.basename(_currentPath!)
                          : 'Remote Files',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.refresh, color: scheme.onPrimary.withValues(alpha: 0.7)),
                  tooltip: 'Refresh',
                  onPressed: () => _browse(_currentPath),
                ),
              ],
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.95),
                    scheme.surface.withValues(alpha: 0.95),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Path breadcrumb bar
                  if (_currentPath != null) _buildBreadcrumb(scheme, canGoUp),
                  // Drop hint
                  _buildDropHint(scheme),
                  // Content
                  Expanded(
                    child: _loading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: scheme.primary,
                            ),
                          )
                        : _error != null
                        ? _buildErrorState(scheme)
                        : _entries.isEmpty
                        ? _buildEmptyState(scheme)
                        : RefreshIndicator(
                            onRefresh: () => _browse(_currentPath),
                            color: scheme.primary,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: _entries.length,
                              itemBuilder: (context, index) =>
                                  _buildEntryTile(scheme, _entries[index]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          // Drag overlay
          if (_dragActive)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: scheme.primary.withValues(alpha: 0.4),
                  child: Center(
                    child: GlassCard(
                      blur: 20,
                      opacity: 0.9,
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upload_file,
                            size: 70,
                            color: scheme.onSurface,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Drop to send to remote device',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(ColorScheme scheme, bool canGoUp) {
    return Container(
      color: scheme.onSurface.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (canGoUp)
            GestureDetector(
              onTap: _navigateUp,
              child: Row(
                children: [
                  Icon(Icons.arrow_upward, color: scheme.onSurface.withValues(alpha: 0.54), size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Up',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.54), fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          Icon(Icons.folder, color: scheme.tertiary, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _currentPath ?? '',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.60), fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropHint(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(10),
        color: scheme.onSurface.withValues(alpha: 0.03),
      ),
      child: Row(
        children: [
          Icon(Icons.upload, color: scheme.onSurface.withValues(alpha: 0.24), size: 16),
          const SizedBox(width: 8),
          Text(
            'Drop local files here to send to remote device',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.24), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: scheme.onSurface.withValues(alpha: 0.24), size: 60),
          const SizedBox(height: 16),
          Text(
            'Could not reach remote device',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.54), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.24), fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _browse(_currentPath),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, color: scheme.onSurface.withValues(alpha: 0.24), size: 60),
          const SizedBox(height: 16),
          Text(
            'This folder is empty',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.38), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(ColorScheme scheme, RemoteFileEntry entry) {
    final progress = _downloadProgress[entry.path];
    final isDownloading = progress != null && progress >= 0 && progress < 1.5;
    final isDone = progress == 2.0;
    final isError = progress == -1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(0),
        child: ListTile(
          onTap: entry.isDir ? () => _navigateInto(entry) : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  (entry.isDir ? scheme.tertiary : _getFileColor(scheme, entry.name))
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              entry.isDir ? Icons.folder : _getFileIcon(entry.name),
              color: entry.isDir
                  ? scheme.tertiary
                  : _getFileColor(scheme, entry.name),
              size: 22,
            ),
          ),
          title: Text(
            entry.name,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                entry.isDir ? 'Folder' : _formatSize(entry.size),
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.54), fontSize: 11),
              ),
              if (isDownloading)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation(
                      scheme.primary,
                    ),
                    minHeight: 3,
                  ),
                ),
              if (isDone)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Downloaded ✓',
                    style: TextStyle(color: scheme.tertiary, fontSize: 11),
                  ),
                ),
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Download failed',
                    style: TextStyle(color: scheme.error, fontSize: 11),
                  ),
                ),
            ],
          ),
          trailing: entry.isDir
              ? Icon(Icons.chevron_right, color: scheme.onSurface.withValues(alpha: 0.38))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.visibility, color: scheme.onSurface.withValues(alpha: 0.7)),
                      tooltip: 'Preview',
                      onPressed: isDownloading
                          ? null
                          : () => _previewFile(entry),
                    ),
                    IconButton(
                      icon: Icon(
                        isDownloading
                            ? Icons.downloading
                            : isDone
                            ? Icons.check_circle
                            : isError
                            ? Icons.error_outline
                            : Icons.download,
                        color: isDone
                            ? scheme.tertiary
                            : isError
                            ? scheme.error
                            : scheme.onSurface.withValues(alpha: 0.7),
                      ),
                      tooltip: 'Download',
                      onPressed: isDownloading
                          ? null
                          : () => _downloadFile(entry),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return Icons.image;
      case '.mp4':
      case '.mov':
      case '.avi':
      case '.mkv':
        return Icons.videocam;
      case '.mp3':
      case '.aac':
      case '.flac':
      case '.wav':
        return Icons.music_note;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return Icons.folder_zip;
      case '.dart':
      case '.py':
      case '.js':
      case '.ts':
      case '.java':
      case '.kt':
      case '.swift':
        return Icons.code;
      case '.txt':
      case '.md':
        return Icons.description;
      case '.apk':
        return Icons.android;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(ColorScheme scheme, String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.pdf':
        return scheme.error;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return scheme.secondary;
      case '.mp4':
      case '.mov':
      case '.avi':
      case '.mkv':
        return Colors.deepOrangeAccent;
      case '.mp3':
      case '.aac':
      case '.flac':
      case '.wav':
        return Colors.pinkAccent;
      case '.zip':
      case '.rar':
      case '.7z':
        return Colors.brown;
      case '.dart':
      case '.py':
      case '.js':
      case '.ts':
        return Colors.cyanAccent;
      case '.apk':
        return Colors.greenAccent;
      default:
        return scheme.primary;
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor().clamp(0, units.length - 1);
    final val = bytes / pow(1024, i);
    return '${val.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }
}
