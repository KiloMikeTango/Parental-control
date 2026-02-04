import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/usage_session.dart';
import '../models/heartbeat_log.dart';
import '../models/interruption.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'parental_control.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Usage sessions table
    await db.execute('''
      CREATE TABLE usage_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT NOT NULL,
        app_name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_ms INTEGER,
        sent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Heartbeat logs table
    await db.execute('''
      CREATE TABLE heartbeat_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL
      )
    ''');

    // Interruptions table
    await db.execute('''
      CREATE TABLE interruptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_time TEXT NOT NULL,
        to_time TEXT NOT NULL,
        duration_ms INTEGER NOT NULL,
        sent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_usage_sessions_sent ON usage_sessions(sent)');
    await db.execute('CREATE INDEX idx_usage_sessions_start_time ON usage_sessions(start_time)');
    await db.execute('CREATE INDEX idx_interruptions_sent ON interruptions(sent)');
  }

  // Usage Sessions
  Future<int> insertUsageSession(UsageSession session) async {
    final db = await database;
    return await db.insert('usage_sessions', session.toMap());
  }

  Future<List<UsageSession>> getUnsentUsageStarts({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'usage_sessions',
      where: 'sent = ? AND end_time IS NULL',
      whereArgs: [0],
      orderBy: 'start_time ASC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => UsageSession.fromMap(maps[i]));
  }

  Future<List<UsageSession>> getUnsentUsageSessions({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'usage_sessions',
      where: 'sent = ? AND end_time IS NOT NULL',
      whereArgs: [0],
      orderBy: 'start_time ASC',
      limit: limit,
    );
    print('DatabaseService: Found ${maps.length} unsent sessions in database');
    return List.generate(maps.length, (i) => UsageSession.fromMap(maps[i]));
  }

  Future<void> markUsageSessionSent(int id) async {
    final db = await database;
    await db.update(
      'usage_sessions',
      {'sent': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteUsageSession(int id) async {
    final db = await database;
    await db.delete(
      'usage_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<UsageSession>> getAllUsageSessions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      where += ' AND start_time >= ?';
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      where += ' AND start_time <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'usage_sessions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'start_time DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => UsageSession.fromMap(maps[i]));
  }

  // Heartbeat Logs
  Future<int> insertHeartbeat(HeartbeatLog heartbeat) async {
    final db = await database;
    return await db.insert('heartbeat_logs', heartbeat.toMap());
  }

  Future<DateTime?> getLastHeartbeat() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'heartbeat_logs',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DateTime.parse(maps[0]['timestamp'] as String);
  }

  // Interruptions
  Future<int> insertInterruption(Interruption interruption) async {
    final db = await database;
    return await db.insert('interruptions', interruption.toMap());
  }

  Future<List<Interruption>> getUnsentInterruptions({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'interruptions',
      where: 'sent = ?',
      whereArgs: [0],
      orderBy: 'from_time ASC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => Interruption.fromMap(maps[i]));
  }

  Future<void> markInterruptionSent(int id) async {
    final db = await database;
    await db.update(
      'interruptions',
      {'sent': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteInterruption(int id) async {
    final db = await database;
    await db.delete(
      'interruptions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Cleanup old data (optional, for maintenance)
  Future<void> deleteOldData(int daysToKeep) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    
    await db.delete(
      'usage_sessions',
      where: 'start_time < ? AND sent = ?',
      whereArgs: [cutoffDate.toIso8601String(), 1],
    );
    
    await db.delete(
      'heartbeat_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );
    
    await db.delete(
      'interruptions',
      where: 'from_time < ? AND sent = ?',
      whereArgs: [cutoffDate.toIso8601String(), 1],
    );
  }
}
