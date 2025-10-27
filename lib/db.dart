import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class AppDb {
  static sqflite.Database? _db;

  static Future<sqflite.Database> instance() async {
    if (_db != null) return _db!;

    // Use FFI on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'kioju', 'kioju_links.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);

    _db = await sqflite.openDatabase(dbPath, version: 1,
        onCreate: (db, version) async {
      await db.execute('''
      CREATE TABLE links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL UNIQUE,
        title TEXT,
        notes TEXT,
        tags TEXT,
        collection TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        remote_id TEXT
      );
      ''');
      await db.execute('''
      CREATE TABLE config (
        key TEXT PRIMARY KEY,
        value TEXT
      );
      ''');
      await db.insert('config', {
        'key': 'base_url',
        'value': 'https://kioju.de/api/api.php'
      });
    });

    return _db!;
  }
}
