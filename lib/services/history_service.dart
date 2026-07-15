import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/clipboard_item.dart';
import '../models/transfer_item.dart';

class HistoryService {
  Database? _db;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ecosystem_history.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clipboard (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT,
            source TEXT,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE transfers (
            id TEXT PRIMARY KEY,
            name TEXT,
            size INTEGER,
            total INTEGER,
            direction TEXT,
            path TEXT,
            status TEXT,
            timestamp INTEGER
          )
        ''');
      },
    );
  }

  // Clipboard History
  Future<void> saveClipboard(ClipboardItem item) async {
    await _db?.insert('clipboard', {
      'text': item.text,
      'source': item.from,
      'timestamp': item.timestamp.millisecondsSinceEpoch,
    });
  }

  Future<List<ClipboardItem>> getClipboardHistory() async {
    final List<Map<String, dynamic>> maps =
        await _db?.query('clipboard', orderBy: 'timestamp DESC', limit: 50) ??
        [];

    return List.generate(maps.length, (i) {
      return ClipboardItem(
        text: maps[i]['text'],
        from: maps[i]['source'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(maps[i]['timestamp']),
      );
    });
  }

  Future<void> clearClipboardHistory() async {
    await _db?.delete('clipboard');
  }

  // Transfer History
  Future<void> saveTransfer(TransferItem item) async {
    await _db?.insert('transfers', {
      'id': item.id,
      'name': item.name,
      'total': item.total,
      'direction': item.direction,
      'path': item.path,
      'status': item.status,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TransferItem>> getTransferHistory() async {
    final List<Map<String, dynamic>> maps =
        await _db?.query('transfers', orderBy: 'timestamp DESC', limit: 100) ??
        [];

    return List.generate(maps.length, (i) {
      return TransferItem(
        id: maps[i]['id'],
        name: maps[i]['name'],
        total: maps[i]['total'],
        direction: maps[i]['direction'],
        path: maps[i]['path'],
        status: maps[i]['status'],
        progress:
            (maps[i]['status'] == 'complete' || maps[i]['status'] == 'failed')
            ? 1.0
            : 0.0,
      );
    });
  }

  Future<void> removeTransfer(String id) async {
    await _db?.delete('transfers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearTransferHistory() async {
    await _db?.delete('transfers');
  }
}
