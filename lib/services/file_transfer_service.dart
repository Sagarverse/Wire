import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileReceiveProgress {
  FileReceiveProgress({required this.name, required this.received, required this.total, required this.path});

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
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/upload') {
        final filename = request.headers.value('x-filename') ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
        final total = int.tryParse(request.headers.value('x-size') ?? '') ?? 0;
        final dir = await _getReceiveDirectory();
        final filePath = p.join(dir.path, filename);
        final file = File(filePath);
        final sink = file.openWrite();
        var received = 0;
        await for (final chunk in request) {
          received += chunk.length;
          sink.add(chunk);
          _receiveProgress.add(FileReceiveProgress(name: filename, received: received, total: total, path: filePath));
        }
        await sink.flush();
        await sink.close();
        _receiveComplete.add(FileReceiveProgress(name: filename, received: received, total: total, path: filePath));
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
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

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    client.idleTimeout = const Duration(seconds: 15);
    try {
      final request = await client.post(host, port, '/upload');
      request.headers.set('x-filename', filename);
      request.headers.set('x-size', length.toString());
      var sent = 0;
      await for (final chunk in file.openRead()) {
        sent += chunk.length;
        request.add(chunk);
        onProgress(sent, length);
      }
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Upload failed with status ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Directory> _getReceiveDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download/Wire');
      if (await downloads.exists() || await downloads.create(recursive: true).then((_) => true).catchError((_) => false)) {
        dir = downloads;
      } else {
        final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        dir = Directory(p.join(base.path, 'ReceivedFiles'));
      }
    } else {
      final base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      dir = Directory(p.join(base.path, 'Wire'));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    await _receiveProgress.close();
    await _receiveComplete.close();
  }
}
