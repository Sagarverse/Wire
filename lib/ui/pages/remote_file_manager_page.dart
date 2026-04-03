import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../providers/remote_file_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/file_action_sheet.dart';
import '../../widgets/liquid_background.dart';

class RemoteFileManagerPage extends StatefulWidget {
  const RemoteFileManagerPage({super.key});

  @override
  State<RemoteFileManagerPage> createState() => _RemoteFileManagerPageState();
}

class _RemoteFileManagerPageState extends State<RemoteFileManagerPage> {
  bool _dragActive = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      context.read<RemoteFileProvider>().setSearchQuery(_searchController.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RemoteFileProvider>().browse(null);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateInto(RemoteFileProvider provider, RemoteFileEntry entry) {
    if (entry.isDir) {
      provider.browse(entry.path);
    } else {
      _showActionSheet(entry, provider);
    }
  }

  void _showActionSheet(RemoteFileEntry entry, RemoteFileProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => FileActionSheet(entry: entry, provider: provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Consumer<RemoteFileProvider>(
      builder: (context, provider, _) {
        final canGoUp = provider.canGoBack;
        
        return DropTarget(
          onDragEntered: (_) => setState(() => _dragActive = true),
          onDragExited: (_) => setState(() => _dragActive = false),
          onDragDone: (details) {
            setState(() => _dragActive = false);
            // In a real app, we'd trigger an upload here.
            // For now, we just show a hint.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upload started...')),
            );
          },
          child: Stack(
            children: [
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: _isSearching 
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search files...',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 16),
                      )
                    : Text(
                        provider.currentPath != null
                            ? p.basename(provider.currentPath!)
                            : 'Remote Files',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                  actions: [
                    IconButton(
                      icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
                      onPressed: () {
                        setState(() {
                          _isSearching = !_isSearching;
                          if (!_isSearching) _searchController.clear();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () => provider.browse(provider.currentPath),
                    ),
                  ],
                ),
                body: LiquidBackground(
                  child: Column(
                    children: [
                      if (provider.currentPath != null) 
                        _buildBreadcrumb(scheme, canGoUp, provider),
                      
                      Expanded(
                        child: provider.isLoading && provider.entries.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : provider.error != null
                            ? _buildErrorState(scheme, provider)
                            : provider.entries.isEmpty
                            ? _buildEmptyState(scheme)
                            : RefreshIndicator(
                                  onRefresh: () => provider.browse(provider.currentPath),
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: provider.entries.length,
                                    itemBuilder: (context, index) =>
                                        _buildEntryTile(scheme, provider.entries[index], provider),
                                  ),
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_dragActive) _buildDragOverlay(scheme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb(ColorScheme scheme, bool canGoUp, RemoteFileProvider provider) {
    final parts = (provider.currentPath ?? '').split('/').where((s) => s.isNotEmpty).toList();
    
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: parts.length + 1,
        separatorBuilder: (_, __) => Icon(Icons.chevron_right_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.2)),
        itemBuilder: (context, index) {
          final isRoot = index == 0;
          final label = isRoot ? 'Phone' : parts[index - 1];
          final isLast = index == parts.length;
          
          return Center(
            child: InkWell(
              onTap: isLast ? null : () {
                if (isRoot) {
                  provider.reset();
                  provider.browse(null);
                } else {
                  final targetPath = '/${parts.sublist(0, index).join('/')}';
                  provider.browse(targetPath);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLast ? scheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isLast ? scheme.primary : scheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntryTile(ColorScheme scheme, RemoteFileEntry entry, RemoteFileProvider provider) {
    final progress = provider.downloadProgress[entry.path];
    final isDownloading = progress != null && progress >= 0 && progress < 1.5;
    final isDone = progress == 2.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          onTap: () => _navigateInto(provider, entry),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (entry.isDir ? scheme.primary : _getFileColor(scheme, entry.name))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              entry.isDir ? Icons.folder_rounded : _getFileIcon(entry.name),
              color: entry.isDir ? scheme.primary : _getFileColor(scheme, entry.name),
              size: 20,
            ),
          ),
          title: Text(
            entry.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            entry.isDir ? 'Folder' : _formatSize(entry.size),
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
          ),
          trailing: entry.isDir
              ? Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDownloading)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    else if (isDone)
                      Icon(Icons.check_circle_rounded, color: scheme.tertiary, size: 22)
                    else
                      IconButton(
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () => provider.downloadFile(entry),
                        style: IconButton.styleFrom(
                          foregroundColor: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme scheme, RemoteFileProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: scheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('Connection Error', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(provider.error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 12)),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => provider.browse(provider.currentPath),
            child: const Text('Retry'),
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
          Icon(Icons.folder_open_rounded, size: 64, color: scheme.onSurface.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('Folder is empty', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3))),
        ],
      ),
    );
  }

  Widget _buildDragOverlay(ColorScheme scheme) {
    return Positioned.fill(
      child: Container(
        color: scheme.primary.withValues(alpha: 0.4),
        child: Center(
          child: GlassCard(
            blur: 20,
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload_file_rounded, size: 70, color: scheme.onSurface),
                const SizedBox(height: 16),
                const Text('Drop to Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper methods cloned from original for consistency
  IconData _getFileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf') return Icons.picture_as_pdf_rounded;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) return Icons.image_rounded;
    if (['.mp4', '.mov', '.avi', '.mkv'].contains(ext)) return Icons.videocam_rounded;
    if (['.mp3', '.aac', '.flac', '.wav'].contains(ext)) return Icons.music_note_rounded;
    if (['.zip', '.rar', '.7z', '.tar', '.gz'].contains(ext)) return Icons.folder_zip_rounded;
    if (['.dart', '.py', '.js', '.ts', '.java', '.kt', '.swift'].contains(ext)) return Icons.code_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(ColorScheme scheme, String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf') return Colors.redAccent;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) return Colors.orangeAccent;
    if (['.mp4', '.mov', '.avi', '.mkv'].contains(ext)) return Colors.purpleAccent;
    if (['.mp3', '.aac', '.flac', '.wav'].contains(ext)) return Colors.pinkAccent;
    if (['.zip', '.rar', '.7z', '.tar', '.gz'].contains(ext)) return Colors.brown;
    return scheme.primary;
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
