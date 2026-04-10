import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/file_transfer_service.dart';

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

class RemoteFileProvider extends ChangeNotifier {
  final FileTransferService _fileTransferService;
  String _peerHost;
  int _filePort;

  List<RemoteFileEntry> _entries = [];
  String _searchQuery = '';
  final List<String?> _pathHistory = [];
  String? _currentPath;
  String? _parentPath;
  bool _isLoading = false;
  String? _error;

  // Tracking downloads: path -> progress (0.0 to 1.0, 2.0 = done, -1.0 = error)
  final Map<String, double> _downloadProgress = {};

  RemoteFileProvider({
    required FileTransferService fileTransferService,
    required String peerHost,
    required int filePort,
  })  : _fileTransferService = fileTransferService,
        _peerHost = peerHost,
        _filePort = filePort;

  void updateConnectionInfo(String host, int port) {
    if (_peerHost != host || _filePort != port) {
      _peerHost = host;
      _filePort = port;
      // If host changed significantly (not just a minor IP update for same device), 
      // we might want to reset, but for now we just update for connectivity.
      notifyListeners();
    }
  }

  List<RemoteFileEntry> get entries => _searchQuery.isEmpty 
    ? _entries 
    : _entries.where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  String? get currentPath => _currentPath;
  String? get parentPath => _parentPath;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  Map<String, double> get downloadProgress => _downloadProgress;
  bool get canGoBack => _pathHistory.isNotEmpty;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> browse(String? path, {bool isBack = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _fileTransferService.browseRemote(
        host: _peerHost,
        port: _filePort,
        path: path,
      );
      
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
    // Preparing for HTTP-based thumbnail API on phone side
    return 'http://$_peerHost:$_filePort/thumb?path=${Uri.encodeComponent(entry.path)}';
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
      await _fileTransferService.downloadRemoteFile(
        host: _peerHost,
        port: _filePort,
        remotePath: entry.path,
        filename: entry.name,
        onProgress: (received, total) {
          if (total > 0) {
            _downloadProgress[entry.path] = received / total;
            notifyListeners();
          }
        },
      );
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
