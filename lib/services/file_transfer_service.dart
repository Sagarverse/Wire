import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileReceiveProgress {
  FileReceiveProgress({
    required this.name,
    required this.received,
    required this.total,
    required this.path,
  });

  final String name;
  final int received;
  final int total;
  final String path;
}

class FileTransferService {
  FileTransferService({this.port = 5758});

  final int port;
  HttpServer? _server;
  final _receiveProgress = StreamController<FileReceiveProgress>.broadcast();
  final _receiveComplete = StreamController<FileReceiveProgress>.broadcast();

  Stream<FileReceiveProgress> get receiveProgress => _receiveProgress.stream;
  Stream<FileReceiveProgress> get receiveComplete => _receiveComplete.stream;

  Future<void> startServer() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server!.listen((request) async {
      debugPrint(
        'File server received request: ${request.method} ${request.uri.path}',
      );
      try {
        if (request.method == 'POST' && request.uri.path == '/upload') {
          final filename =
              request.headers.value('x-filename') ??
              'file_${DateTime.now().millisecondsSinceEpoch}';
          final total =
              int.tryParse(request.headers.value('x-size') ?? '') ?? 0;
          debugPrint('Incoming file: $filename, expected size: $total bytes');
          final dir = await _getReceiveDirectory();
          final filePath = p.join(dir.path, filename);
          debugPrint('Saving to: $filePath');
          final file = File(filePath);
          IOSink? sink;
          var received = 0;
          try {
            sink = file.openWrite();
            await for (final chunk in request) {
              received += chunk.length;
              sink.add(chunk);
              debugPrint('Received $received / $total bytes for $filename');
              _receiveProgress.add(
                FileReceiveProgress(
                  name: filename,
                  received: received,
                  total: total,
                  path: filePath,
                ),
              );
            }
            await sink.flush();
            await sink.close();
            _receiveComplete.add(
              FileReceiveProgress(
                name: filename,
                received: total,
                total: total,
                path: filePath,
              ),
            );
            request.response.statusCode = HttpStatus.ok;
            request.response.write('OK');
          } catch (e) {
            debugPrint('Error during file receive: $e');
            await sink?.close();
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Error: $e');
          } finally {
            await request.response.close();
          }
        } else if (request.method == 'GET' && request.uri.path == '/browse') {
          // --- Remote File Browser: list directory ---
          final rawPath = request.uri.queryParameters['path'] ?? '';
          final Directory browseDir = rawPath.isNotEmpty
              ? Directory(rawPath)
              : await _getReceiveDirectory();
          if (!await browseDir.exists()) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(
              jsonEncode({'error': 'Directory not found'}),
            );
            await request.response.close();
          } else {
            final entries = browseDir.listSync()
              ..sort((a, b) {
                // Directories first, then alphabetical
                final aIsDir = a is Directory ? 0 : 1;
                final bIsDir = b is Directory ? 0 : 1;
                if (aIsDir != bIsDir) return aIsDir - bIsDir;
                return p.basename(a.path).compareTo(p.basename(b.path));
              });
            final list = entries.map((e) {
              final isDir = e is Directory;
              int size = 0;
              int modified = 0;
              try {
                final stat = e.statSync();
                size = stat.size;
                modified = stat.modified.millisecondsSinceEpoch;
              } catch (_) {}
              return {
                'name': p.basename(e.path),
                'path': e.path,
                'isDir': isDir,
                'size': size,
                'modified': modified,
              };
            }).toList();
            // Include parent dir info
            final parentPath = browseDir.parent.path;
            final responseBody = jsonEncode({
              'currentPath': browseDir.path,
              'parentPath': parentPath != browseDir.path ? parentPath : null,
              'entries': list,
            });
            request.response.headers.contentType = ContentType.json;
            request.response.headers.set('Access-Control-Allow-Origin', '*');
            request.response.write(responseBody);
            await request.response.close();
          }
        } else if (request.method == 'GET' && request.uri.path == '/download') {
          // --- Remote File Download: stream file ---
          final filePath = request.uri.queryParameters['path'] ?? '';
          if (filePath.isEmpty || !await File(filePath).exists()) {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('File not found');
            await request.response.close();
          } else {
            final file = File(filePath);
            final length = await file.length();
            final filename = p.basename(filePath);
            request.response.headers.contentLength = length;
            request.response.headers.set(
              'Content-Disposition',
              'attachment; filename="$filename"',
            );
            request.response.headers.set(
              'Content-Type',
              'application/octet-stream',
            );
            debugPrint('Sending file for download: $filename ($length bytes)');
            await file.openRead().pipe(request.response);
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      } catch (e) {
        debugPrint('Server error: $e');
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    });
  }

  Future<void> sendFile({
    required String filePath,
    required String host,
    required int port,
    required void Function(int sent, int total) onProgress,
  }) async {
    final file = File(filePath);
    final length = await file.length();
    final filename = p.basename(filePath);

    var attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      attempts++;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      client.idleTimeout = const Duration(seconds: 30);

      try {
        final request = await client.post(host, port, '/upload');
        request.headers.set('x-filename', filename);
        request.headers.set('x-size', length.toString());
        request.contentLength =
            length; // Explicitly set length to avoid chunked encoding

        var sent = 0;
        // Use a larger buffer for reading
        final stream = file.openRead();
        await for (final chunk in stream) {
          sent += chunk.length;
          request.add(chunk);
          onProgress(sent, length);
        }

        final response = await request.close().timeout(
          const Duration(minutes: 5),
        );
        if (response.statusCode == HttpStatus.ok) {
          return; // Success
        } else {
          throw HttpException(
            'Upload failed with status ${response.statusCode}',
          );
        }
      } catch (e) {
        if (attempts >= maxAttempts) {
          rethrow;
        }
        // Exponential backoff
        await Future.delayed(Duration(seconds: 2 * attempts));
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<Directory> _getReceiveDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download/Wire');
      if (await downloads.exists() ||
          await downloads
              .create(recursive: true)
              .then((_) => true)
              .catchError((_) => false)) {
        dir = downloads;
      } else {
        final base =
            await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        dir = Directory(p.join(base.path, 'ReceivedFiles'));
      }
    } else {
      final base =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      dir = Directory(p.join(base.path, 'Wire'));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Browse a remote directory via the /browse endpoint.
  Future<Map<String, dynamic>> browseRemote({
    required String host,
    required int port,
    String? path,
  }) async {
    final queryParams = path != null ? {'path': path} : <String, String>{};
    final uri = Uri.http('$host:$port', '/browse', queryParams);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder()).join();
      if (response.statusCode == HttpStatus.ok) {
        return jsonDecode(body) as Map<String, dynamic>;
      } else {
        throw HttpException('Browse failed: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  /// Download a file from the remote device, saving it to local Downloads.
  Future<String> downloadRemoteFile({
    required String host,
    required int port,
    required String remotePath,
    required String filename,
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.http('$host:$port', '/download', {'path': remotePath});
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Download failed: ${response.statusCode}');
      }
      final total = response.contentLength;
      final dir = await _getReceiveDirectory();
      final localPath = p.join(dir.path, filename);
      final file = File(localPath);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (onProgress != null) onProgress(received, total);
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        rethrow;
      }
      debugPrint('Downloaded $filename to $localPath');
      return localPath;
    } finally {
      client.close();
    }
  }

  /// Download a file from the remote device, saving it to a temporary directory.
  Future<String> downloadRemoteFileToTemp({
    required String host,
    required int port,
    required String remotePath,
    required String filename,
    void Function(int received, int total)? onProgress,
  }) async {
    final uri = Uri.http('$host:$port', '/download', {'path': remotePath});
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Download failed: ${response.statusCode}');
      }
      final total = response.contentLength;
      final dir = await getTemporaryDirectory();
      final localPath = p.join(dir.path, filename);
      final file = File(localPath);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (onProgress != null) onProgress(received, total);
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        rethrow;
      }
      debugPrint('Downloaded temp file $filename to $localPath');
      return localPath;
    } finally {
      client.close();
    }
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    await _receiveProgress.close();
    await _receiveComplete.close();
  }
}
