import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../providers/app_state.dart';
import '../../providers/remote_file_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/file_action_sheet.dart';
import '../../widgets/liquid_background.dart';

class DesktopBrowserPage extends StatefulWidget {
  const DesktopBrowserPage({super.key});

  @override
  State<DesktopBrowserPage> createState() => _DesktopBrowserPageState();
}

class _DesktopBrowserPageState extends State<DesktopBrowserPage> {
  String _currentPath = '';
  List<RemoteFileEntry> _entries = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final List<String> _pathHistory = [];

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory([String? path]) async {
    setState(() => _isLoading = true);
    final appState = context.read<AppState>();
    final activeDevice = appState.pairingService.activeDevice;

    if (activeDevice == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final result = await appState.fileTransferService.browseRemote(
        host: activeDevice.lastIp,
        port: 5758,
        path: path,
      );

      setState(() {
        _currentPath = result['currentPath'];
        _entries = (result['entries'] as List)
            .map((e) => RemoteFileEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        if (path != null && !_pathHistory.contains(path)) {
          _pathHistory.add(path);
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load: $e')),
      );
    }
  }

  List<RemoteFileEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    return _entries.where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('MAC DESKTOP', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _loadDirectory(_currentPath),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(scheme),
            _buildBreadcrumbs(scheme),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredEntries.isEmpty
                      ? _buildEmptyState(scheme)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _filteredEntries.length,
                          itemBuilder: (context, index) => _buildFileItem(_filteredEntries[index], scheme),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassCard(
        accent: scheme.primary,
        padding: EdgeInsets.zero,
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Search files on Mac...',
            hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.search_rounded, color: scheme.primary),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(ColorScheme scheme) {
    final parts = _currentPath.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();
    
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: parts.length,
        itemBuilder: (context, index) {
          final isLast = index == parts.length - 1;
          return Row(
            children: [
              GestureDetector(
                onTap: () {
                   final targetPath = Platform.pathSeparator + parts.take(index + 1).join(Platform.pathSeparator);
                   _loadDirectory(targetPath);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLast ? scheme.primary.withValues(alpha: 0.1) : scheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    parts[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isLast ? FontWeight.w900 : FontWeight.bold,
                      color: isLast ? scheme.primary : scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              if (!isLast) Icon(Icons.chevron_right_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.2)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFileItem(RemoteFileEntry entry, ColorScheme scheme) {
    final bool isDir = entry.isDir;
    final String name = entry.name;
    final String path = entry.path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCardInteractive(
        onTap: () {
          if (isDir) {
            _loadDirectory(path);
          } else {
            _showActionSheet(entry);
          }
        },
        accent: isDir ? scheme.secondary : scheme.primary,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isDir ? scheme.secondary : scheme.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isDir ? Icons.folder_rounded : _getFileIcon(name),
                color: isDir ? scheme.secondary : scheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  if (!isDir)
                    Text(
                      _getFileSize(entry.size),
                      style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            Icon(isDir ? Icons.arrow_forward_ios_rounded : Icons.more_vert_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.2)),
          ],
        ),
      ),
    );
  }

  void _showActionSheet(RemoteFileEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FileActionSheet(
        entry: entry,
        provider: Provider.of<RemoteFileProvider>(context, listen: false),
      ),
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png': return Icons.image_rounded;
      case 'mp4':
      case 'mov': return Icons.video_library_rounded;
      case 'mp3':
      case 'wav': return Icons.audiotrack_rounded;
      case 'zip':
      case 'rar': return Icons.archive_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  String _getFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: scheme.onSurface.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text(
            'Empty Directory',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }
}
