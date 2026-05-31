import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static const String _databaseName = 'dna_database.db';
  static const int _databaseVersion = 2;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String dbPath = path.join(documentsDirectory.path, _databaseName);

    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tas (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        gender TEXT NOT NULL,
        persona TEXT NOT NULL,
        intro TEXT NOT NULL,
        opening TEXT NOT NULL,
        tags TEXT NOT NULL,
        images TEXT NOT NULL,
        dialogue_style TEXT NOT NULL,
        original_link TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE worlds (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '[]',
        forbidden_words TEXT NOT NULL DEFAULT '[]',
        entries TEXT NOT NULL DEFAULT '[]',
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        ta_id TEXT NOT NULL,
        world_id TEXT,
        note TEXT NOT NULL DEFAULT '',
        background_mode TEXT NOT NULL DEFAULT 'none',
        archived INTEGER NOT NULL DEFAULT 0,
        is_group INTEGER NOT NULL DEFAULT 0,
        group_name TEXT NOT NULL DEFAULT '',
        group_prompt TEXT NOT NULL DEFAULT '',
        member_ta_ids TEXT NOT NULL DEFAULT '[]',
        active_ta_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE conversation_messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'message',
        summary_id TEXT,
        anchor_message_id TEXT,
        speaker_ta_id TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE conversation_summaries (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        end_message_id TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_snapshots (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        name TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        data TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_conversations_ta_id ON conversations(ta_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_conversations_archived ON conversations(archived)
    ''');
    await db.execute('''
      CREATE INDEX idx_messages_conversation_id ON conversation_messages(conversation_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_messages_timestamp ON conversation_messages(timestamp)
    ''');
    await db.execute('''
      CREATE INDEX idx_summaries_conversation_id ON conversation_summaries(conversation_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_snapshots_conversation_id ON chat_snapshots(conversation_id)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add original_link column to tas table
      await db.execute('ALTER TABLE tas ADD COLUMN original_link TEXT');
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> deleteDatabase() async {
    await close();
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String dbPath = path.join(documentsDirectory.path, _databaseName);
    final File dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  }
}
