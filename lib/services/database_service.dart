import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:archive/archive.dart';
import '../models/page_model.dart';
import '../models/card_model.dart';

class DatabaseService {
  Database? _db;
  String? _currentWorkspacePath;

  bool get isOpen => _db != null;

  String get currentWorkspaceName {
    if (_currentWorkspacePath == null) return '';
    return basenameWithoutExtension(_currentWorkspacePath!);
  }

  String get currentWorkspacePath => _currentWorkspacePath ?? '';

  Future<Database> get database async {
    if (_db != null) return _db!;
    throw StateError(
      'No active workspace. Call switchWorkspace() or openDefaultWorkspace() first.',
    );
  }

  // --- Workspace Management ---

  Future<Directory> getWorkspaceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(join(appDir.path, 'cero_workspaces'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<String>> listWorkspaces() async {
    final dir = await getWorkspaceDirectory();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.db'))
        .map((file) => file.path)
        .toList();
    files.sort();
    return files;
  }

  Future<void> switchWorkspace(String filePath) async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _currentWorkspacePath = filePath;
    _db = await _openDatabase(filePath);
  }

  Future<void> openDefaultWorkspace() async {
    final dir = await getWorkspaceDirectory();
    final defaultPath = join(dir.path, 'Personal.db');
    await switchWorkspace(defaultPath);
  }

  Future<void> createWorkspace(String name) async {
    final dir = await getWorkspaceDirectory();
    final path = join(dir.path, '$name.db');
    if (await File(path).exists()) {
      await switchWorkspace(path);
      return;
    }
    await switchWorkspace(path);
  }

  Future<void> deleteWorkspace(String filePath) async {
    if (_currentWorkspacePath == filePath) {
      if (_db != null) {
        await _db!.close();
        _db = null;
      }
      _currentWorkspacePath = null;
    }
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    final wsName = basenameWithoutExtension(filePath);
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/cero_workspaces/${wsName}_images');
    if (await imageDir.exists()) {
      await imageDir.delete(recursive: true);
    }
  }

  // --- Database Initialization ---

  void _initFfi() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<Database> _openDatabase(String dbPath) async {
    _initFfi();
    debugPrint('Opening workspace: $dbPath');

    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );

    await _migrateLegacyData(db);
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pages (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        relation_type TEXT NOT NULL DEFAULT 'subpage',
        title TEXT NOT NULL,
        emoji TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY,
        page_id TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (page_id) REFERENCES pages (id) ON DELETE CASCADE
      )
    ''');

    // Insert default welcome pages
    final now = DateTime.now();
    await db.insert('pages', {
      'id': 'root-welcome',
      'parent_id': null,
      'relation_type': 'subpage',
      'title': 'Welcome to Cero',
      'emoji': '📓',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'is_archived': 0,
      'sort_order': 0,
      'revision': 0,
    });

    await db.insert('cards', {
      'id': 'root-welcome-card-0',
      'page_id': 'root-welcome',
      'type': 'markdown',
      'content': '# Welcome to Cero!\n\nCero is your personal, offline-first nested markdown journal.\n\n### Core Features:\n- **Infinite Nesting**: Create pages inside pages inside pages.\n- **Block Cards**: Each page is a column of markdown, image, and link cards.\n- **Multi-Workspace**: Switch between different `.db` workspace files.\n- **Sleek Notion Aesthetics**: Minimalist dark mode with emoji icons.\n- **Mobile-first Truth**: Your phone holds the database. Connecting from your laptop syncs editing in real time.\n\n*Click on the subpage below in the sidebar to explore more!*',
      'sort_order': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'revision': 0,
    });

    await db.insert('pages', {
      'id': 'child-journal-tips',
      'parent_id': 'root-welcome',
      'relation_type': 'subpage',
      'title': 'Journaling Tips',
      'emoji': '📝',
      'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'updated_at': now.toIso8601String(),
      'is_archived': 0,
      'sort_order': 0,
      'revision': 0,
    });

    await db.insert('cards', {
      'id': 'child-journal-tips-card-0',
      'page_id': 'child-journal-tips',
      'type': 'markdown',
      'content': '# Journaling Tips 📝\n\nHere are some ideas to help you write daily in Cero:\n\n1. **Morning Dump**: Write 3 pages of stream-of-consciousness writing to clear your head.\n2. **Bullet Logs**: Keep a simple bullet list of things you accomplished today.\n3. **Gratitude**: List 3 things you are grateful for today.\n\nFeel free to modify this page or delete it!',
      'sort_order': 0,
      'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'updated_at': now.toIso8601String(),
      'revision': 0,
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          "ALTER TABLE pages ADD COLUMN relation_type TEXT NOT NULL DEFAULT 'subpage'",
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE pages ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS cards (
          id TEXT PRIMARY KEY,
          page_id TEXT NOT NULL,
          type TEXT NOT NULL,
          content TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (page_id) REFERENCES pages (id) ON DELETE CASCADE
        )
      ''');
    }
  }

  // --- Legacy Migration ---

  Future<void> _migrateLegacyData(Database db) async {
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='pages'");
    if (tables.isEmpty) return;

    final columns = await db.rawQuery("PRAGMA table_info(pages)");
    final hasContentCol = columns.any((c) => c['name'] == 'content');

    if (!hasContentCol) return;

    debugPrint('Migrating legacy data: content column → cards table');

    final legacyPages = await db.query('pages');
    for (var legacy in legacyPages) {
      final pageId = legacy['id'] as String;
      final content = legacy['content'] as String?;

      if (content != null && content.trim().isNotEmpty) {
        final existingCards = await db.query(
          'cards',
          where: 'page_id = ?',
          whereArgs: [pageId],
        );
        if (existingCards.isEmpty) {
          await db.insert('cards', {
            'id': '$pageId-card-0',
            'page_id': pageId,
            'type': 'markdown',
            'content': content,
            'sort_order': 0,
            'created_at': legacy['created_at'],
            'updated_at': legacy['updated_at'],
            'revision': 0,
          });
        }
      }
    }

    try {
      await db.execute('ALTER TABLE pages DROP COLUMN content');
      debugPrint('Dropped legacy content column');
    } catch (e) {
      debugPrint('Could not drop content column (may not be supported): $e');
    }
  }

  // --- Page CRUD ---

  Future<List<DbPage>> getAllPages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pages',
      where: 'is_archived = 0',
      orderBy: 'sort_order ASC, created_at DESC',
    );
    return List.generate(maps.length, (i) => DbPage.fromMap(maps[i]));
  }

  Future<List<DbPage>> getSubpages(String? parentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pages',
      where: 'parent_id ${parentId == null ? 'IS NULL' : '= ?'} AND relation_type = ? AND is_archived = 0',
      whereArgs: parentId == null ? ['subpage'] : [parentId, 'subpage'],
      orderBy: 'sort_order ASC, created_at DESC',
    );
    return List.generate(maps.length, (i) => DbPage.fromMap(maps[i]));
  }

  Future<List<DbPage>> getSidePages(String parentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'pages',
      where: 'parent_id = ? AND relation_type = ? AND is_archived = 0',
      whereArgs: [parentId, 'sidepage'],
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
    final List<Map<String, dynamic>> children = await txn.query(
      'pages',
      columns: ['id'],
      where: 'parent_id = ? AND is_archived = 0',
      whereArgs: [id],
    );

    for (var child in children) {
      final childId = child['id'] as String;
      await _archivePageAndChildrenTxn(txn, childId);
    }

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
    final List<Map<String, dynamic>> children = await txn.query(
      'pages',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [id],
    );

    for (var child in children) {
      final childId = child['id'] as String;
      await _restorePageAndChildrenTxn(txn, childId);
    }

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
    await txn.delete('cards', where: 'page_id = ?', whereArgs: [id]);

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

    await txn.delete('pages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('cards');
    await db.delete('pages');
  }

  // --- Card CRUD ---

  Future<List<Card>> getCards(String pageId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'cards',
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'sort_order ASC',
    );
    return List.generate(maps.length, (i) => Card.fromMap(maps[i]));
  }

  Future<Card?> getCard(String cardId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'cards',
      where: 'id = ?',
      whereArgs: [cardId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Card.fromMap(maps.first);
  }

  Future<void> insertCard(Card card) async {
    final db = await database;
    await db.insert(
      'cards',
      card.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCard(Card card) async {
    final db = await database;
    await db.update(
      'cards',
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<void> deleteCard(String cardId) async {
    final db = await database;
    await db.delete('cards', where: 'id = ?', whereArgs: [cardId]);
  }

  Future<void> deleteCardsForPage(String pageId) async {
    final db = await database;
    await db.delete('cards', where: 'page_id = ?', whereArgs: [pageId]);
  }

  Future<void> reorderCards(String pageId, List<String> cardIds) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < cardIds.length; i++) {
        await txn.update(
          'cards',
          {'sort_order': i},
          where: 'id = ? AND page_id = ?',
          whereArgs: [cardIds[i], pageId],
        );
      }
    });
  }

  Future<void> updateCardSortOrder(String cardId, int newOrder) async {
    final db = await database;
    await db.update(
      'cards',
      {'sort_order': newOrder},
      where: 'id = ?',
      whereArgs: [cardId],
    );
  }

  // --- Image Storage ---

  Future<Directory> _getImageDir() async {
    final wsName = currentWorkspaceName;
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/cero_workspaces/${wsName}_images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  Future<String> saveImage(Uint8List imageBytes, String originalName) async {
    final dir = await _getImageDir();
    final ext = originalName.contains('.')
        ? originalName.substring(originalName.lastIndexOf('.'))
        : '.png';
    final filename = '${DateTime.now().millisecondsSinceEpoch}_$ext';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(imageBytes);
    return filename;
  }

  Future<String?> getImagePath(String filename) async {
    final dir = await _getImageDir();
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  Future<void> deleteImage(String filename) async {
    final dir = await _getImageDir();
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      await file.delete();
    }
  }

  // --- Backup & Restore (Zip Packing) ---

  Future<String> getExportDirectoryPath() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) {
        return dir.path;
      }
    }
    final docDir = await getApplicationDocumentsDirectory();
    return docDir.path;
  }

  Future<String> exportWorkspaceToZip(String workspaceName, String targetDirectoryPath) async {
    final dir = await getWorkspaceDirectory();
    final dbFile = File(join(dir.path, '$workspaceName.db'));
    final imageDir = Directory(join(dir.path, '${workspaceName}_images'));

    final archive = Archive();

    // 1. Add DB file
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));
    }

    // 2. Add all image files recursively
    if (await imageDir.exists()) {
      final List<FileSystemEntity> entities = await imageDir.list(recursive: true).toList();
      for (final entity in entities) {
        if (entity is File) {
          final relativePath = relative(entity.path, from: imageDir.path);
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile('images/$relativePath', bytes.length, bytes));
        }
      }
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Failed to encode zip archive');
    }

    final sanitizedName = workspaceName.replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final filename = 'Cero_Backup_$sanitizedName.zip';

    try {
      final targetPath = join(targetDirectoryPath, filename);
      final zipFile = File(targetPath);
      await zipFile.create(recursive: true);
      await zipFile.writeAsBytes(zipData);
      return targetPath;
    } catch (e) {
      debugPrint('Direct public Download write failed: $e. Saving to applicationScoped local storage.');
      final docDir = await getApplicationDocumentsDirectory();
      final fallbackPath = join(docDir.path, filename);
      final fallbackFile = File(fallbackPath);
      await fallbackFile.create(recursive: true);
      await fallbackFile.writeAsBytes(zipData);
      return fallbackPath;
    }
  }

  Future<void> importWorkspaceFromZip(String sourceZipPath, String targetWorkspaceName) async {
    final zipFile = File(sourceZipPath);
    if (!await zipFile.exists()) {
      throw Exception('Source zip file does not exist');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final dir = await getWorkspaceDirectory();
    final targetDbFile = File(join(dir.path, '$targetWorkspaceName.db'));
    final targetImageDir = Directory(join(dir.path, '${targetWorkspaceName}_images'));

    final isCurrent = currentWorkspaceName == targetWorkspaceName;
    if (isCurrent && _db != null) {
      await _db!.close();
      _db = null;
    }

    if (await targetImageDir.exists()) {
      await targetImageDir.delete(recursive: true);
    }
    await targetImageDir.create(recursive: true);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        if (filename == 'database.db') {
          await targetDbFile.writeAsBytes(data);
        } else if (filename.startsWith('images/')) {
          final relativePath = filename.substring('images/'.length);
          final outFile = File(join(targetImageDir.path, relativePath));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }
    }

    if (isCurrent) {
      await switchWorkspace(targetDbFile.path);
    }
  }
}
