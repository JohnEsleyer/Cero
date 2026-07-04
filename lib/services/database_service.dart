import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/page_model.dart';

class DatabaseService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite not supported on Web in this demo.');
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Initialize ffi for desktop platforms during dev/testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(dbDirectory.path, 'cero_journal.db');
    debugPrint('Database path: $dbPath');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pages (
            id TEXT PRIMARY KEY,
            parent_id TEXT,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            emoji TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');

        // Insert some default welcome pages
        final now = DateTime.now();
        await db.insert('pages', {
          'id': 'root-welcome',
          'parent_id': null,
          'title': 'Welcome to Cero 📓',
          'content': '# Welcome to Cero!\n\nCero is your personal, offline-first nested markdown journal. \n\n### Core Features:\n- **Infinite Nesting**: Create pages inside pages inside pages.\n- **Sleek Notion Aesthetics**: Minimalist dark mode with emoji icons.\n- **Mobile-first Truth**: Your phone holds the database. Connecting from your laptop syncs editing in real time.\n\n*Click on the subpage below in the sidebar to explore more!*',
          'emoji': '📓',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'is_archived': 0,
          'sort_order': 0,
        });

        await db.insert('pages', {
          'id': 'child-journal-tips',
          'parent_id': 'root-welcome',
          'title': 'Journaling Tips',
          'content': '# Journaling Tips 📝\n\nHere are some ideas to help you write daily in Cero:\n\n1. **Morning Dump**: Write 3 pages of stream-of-consciousness writing to clear your head.\n2. **Bullet Logs**: Keep a simple bullet list of things you accomplished today.\n3. **Gratitude**: List 3 things you are grateful for today.\n\nFeel free to modify this page or delete it!',
          'emoji': '📝',
          'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
          'updated_at': now.toIso8601String(),
          'is_archived': 0,
          'sort_order': 0,
        });
      },
    );
  }

  Future<List<DbPage>> getAllPages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pages',
      where: 'is_archived = 0',
      orderBy: 'sort_order ASC, created_at DESC',
    );
    return List.generate(maps.length, (i) => DbPage.fromMap(maps[i]));
  }

  Future<void> insertPage(DbPage page) async {
    final db = await database;
    await db.insert(
      'pages',
      page.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePage(DbPage page) async {
    final db = await database;
    await db.update(
      'pages',
      page.toMap(),
      where: 'id = ?',
      whereArgs: [page.id],
    );
  }

  Future<void> archivePageRecursive(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _archivePageAndChildrenTxn(txn, id);
    });
  }

  Future<void> _archivePageAndChildrenTxn(Transaction txn, String id) async {
    // 1. Find all children
    final List<Map<String, dynamic>> children = await txn.query(
      'pages',
      columns: ['id'],
      where: 'parent_id = ? AND is_archived = 0',
      whereArgs: [id],
    );

    // 2. Recursively archive children
    for (var child in children) {
      final childId = child['id'] as String;
      await _archivePageAndChildrenTxn(txn, childId);
    }

    // 3. Archive the page itself (soft delete)
    await txn.update(
      'pages',
      {'is_archived': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restorePageRecursive(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _restorePageAndChildrenTxn(txn, id);
    });
  }

  Future<void> _restorePageAndChildrenTxn(Transaction txn, String id) async {
    // 1. Find all children (also archived)
    final List<Map<String, dynamic>> children = await txn.query(
      'pages',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [id],
    );

    // 2. Recursively restore children
    for (var child in children) {
      final childId = child['id'] as String;
      await _restorePageAndChildrenTxn(txn, childId);
    }

    // 3. Restore the page itself
    await txn.update(
      'pages',
      {'is_archived': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<DbPage>> getArchivedPages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pages',
      where: 'is_archived = 1',
      orderBy: 'updated_at DESC',
    );
    return List.generate(maps.length, (i) => DbPage.fromMap(maps[i]));
  }

  Future<void> hardDeletePageRecursive(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _hardDeletePageAndChildrenTxn(txn, id);
    });
  }

  Future<void> _hardDeletePageAndChildrenTxn(Transaction txn, String id) async {
    final List<Map<String, dynamic>> children = await txn.query(
      'pages',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [id],
    );

    for (var child in children) {
      final childId = child['id'] as String;
      await _hardDeletePageAndChildrenTxn(txn, childId);
    }

    await txn.delete(
      'pages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('pages');
  }
}
