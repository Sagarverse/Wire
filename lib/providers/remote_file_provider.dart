import 'dart:async';
import 'package:flutter/foundation.dart';
import 'app_state.dart';

class RemoteFileEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int modified;

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
}

enum RemoteFileSort { name, size, date }

class RemoteFileProvider extends ChangeNotifier {
  final AppState _appState;

  List<RemoteFileEntry> _entries = [];
  String _searchQuery = '';
  final List<String?> _pathHistory = [];
  String? _currentPath;
  String? _parentPath;
  bool _isLoading = false;
  String? _error;
  bool _isGridView = false;
  RemoteFileSort _sortMode = RemoteFileSort.name;
  bool _isAscending = true;

  // Tracking downloads: path -> progress (0.0 to 1.0, 2.0 = done, -1.0 = error)
  final Map<String, double> _downloadProgress = {};

  RemoteFileProvider({
    required AppState appState,
  }) : _appState = appState;

  void updateConnectionInfo(String host, int port) {
    // No-op: AppState handles connection info internally
  }

  List<RemoteFileEntry> get entries {
    var list = _searchQuery.isEmpty 
      ? List<RemoteFileEntry>.from(_entries) 
      : _entries.where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int cmp = 0;
      switch (_sortMode) {
        case RemoteFileSort.size:
          cmp = a.size.compareTo(b.size);
          break;
        case RemoteFileSort.date:
          cmp = a.modified.compareTo(b.modified);
          break;
        case RemoteFileSort.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
      }
      return _isAscending ? cmp : -cmp;
    });
    return list;
  }

  String? get currentPath => _currentPath;
  String? get parentPath => _parentPath;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  Map<String, double> get downloadProgress => _downloadProgress;
  bool get canGoBack => _pathHistory.isNotEmpty;
  bool get isGridView => _isGridView;
  RemoteFileSort get sortMode => _sortMode;
  bool get isAscending => _isAscending;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void setSort(RemoteFileSort mode, {bool? ascending}) {
    _sortMode = mode;
    if (ascending != null) _isAscending = ascending;
    notifyListeners();
  }

  Future<void> browse(String? path, {bool isBack = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _appState.browseRemote(path);
      
      if (!isBack && _currentPath != null) {
        _pathHistory.add(_currentPath);
      }

      _currentPath = result['currentPath']?.toString();
      _parentPath = result['parentPath']?.toString();
      _entries = (result['entries'] as List<dynamic>? ?? [])
          .map((e) => RemoteFileEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> goBack() async {
    if (_pathHistory.isEmpty) return;
    final last = _pathHistory.removeLast();
    await browse(last, isBack: true);
  }

  String getThumbnailUrl(RemoteFileEntry entry) {
    final active = _appState.pairingService.activeDevice;
    if (active == null) return '';
    return 'http://${active.lastIp}:${active.filePort}/thumb?path=${Uri.encodeComponent(entry.path)}';
  }

  void reset() {
    _entries = [];
    _currentPath = null;
    _parentPath = null;
    _error = null;
    _downloadProgress.clear();
    _pathHistory.clear();
    _searchQuery = '';
    notifyListeners();
  }
  Future<void> downloadFile(RemoteFileEntry entry) async {
    _downloadProgress[entry.path] = 0.0;
    notifyListeners();

    try {
      if (_appState.webSocketService.isConnected) {
        final active = _appState.pairingService.activeDevice!;
        await _appState.fileTransferService.downloadRemoteFile(
          host: active.lastIp,
          port: active.filePort,
          remotePath: entry.path,
          filename: entry.name,
          onProgress: (received, total) {
            if (total > 0) {
              _downloadProgress[entry.path] = received / total;
              notifyListeners();
            }
          },
        );
      } else {
        // P2P/Internet Path: Ask remote to PUSH the file to us
        await _appState.requestP2PDownload(entry.path);
        // Note: Progress for P2P is handled by AppState updating the lastReceivedFile
        _downloadProgress[entry.path] = 1.0; // Mark as started
      }
      _downloadProgress[entry.path] = 2.0; // Done
      notifyListeners();
      
      // Auto-clear success after delay
      Future.delayed(const Duration(seconds: 3), () {
        _downloadProgress.remove(entry.path);
        notifyListeners();
      });
    } catch (e) {
      _downloadProgress[entry.path] = -1.0; // Error
      notifyListeners();
      
      Future.delayed(const Duration(seconds: 5), () {
        _downloadProgress.remove(entry.path);
        notifyListeners();
      });
    }
  }
}
