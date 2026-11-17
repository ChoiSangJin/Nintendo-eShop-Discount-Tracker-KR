import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite shares atomic catalog snapshots and a renewable collection lease
/// between the foreground Flutter engine and WorkManager's separate engine.
class CatalogDatabase {
  CatalogDatabase(this.db);
  final Database db;
  Map<String, dynamic>? snapshot;
  String? _owner;
  Timer? _heartbeat;

  static Future<CatalogDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final dbPath =
        path ??
        '${(await getApplicationSupportDirectory()).path}/catalog_shared_v1.db';
    final db = await (factory ?? databaseFactory).openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA busy_timeout = 0');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    final result = CatalogDatabase(db);
    await result.reload();
    return result;
  }

  // Never block sqflite's shared native queue while another connection needs
  // that same queue to commit its transaction (also applies to older Android).
  Future<T> _retryBusy<T>(Future<T> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } on DatabaseException catch (error) {
        if (attempt >= 49 || !error.toString().contains('database is locked')) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  Future<void> reload() async {
    final rows = await db.query(
      'state',
      where: 'key = ?',
      whereArgs: ['catalog'],
    );
    snapshot = rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          );
  }

  Future<void> save(Map<String, dynamic> value) async {
    await _retryBusy(
      () => db.transaction((tx) async {
        if (_owner != null) {
          final lease = await tx.query(
            'state',
            where: 'key = ?',
            whereArgs: ['lease'],
          );
          if (lease.isEmpty ||
              (jsonDecode(lease.single['value'] as String) as Map)['owner'] !=
                  _owner) {
            throw StateError('Collection lease was replaced');
          }
        }
        await tx.insert('state', {
          'key': 'catalog',
          'value': jsonEncode(value),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }),
    );
    snapshot = value;
  }

  Future<bool> acquire(DateTime now) async {
    final owner = '${now.microsecondsSinceEpoch}-${identityHashCode(this)}';
    final acquired = await _retryBusy(
      () => db.transaction((tx) async {
        final rows = await tx.query(
          'state',
          where: 'key = ?',
          whereArgs: ['lease'],
        );
        if (rows.isNotEmpty) {
          final lease = jsonDecode(rows.single['value'] as String) as Map;
          if (DateTime.parse(lease['expires'] as String).isAfter(now)) {
            return false;
          }
        }
        await tx.insert('state', {
          'key': 'lease',
          'value': jsonEncode({
            'owner': owner,
            'expires': now.add(const Duration(minutes: 3)).toIso8601String(),
          }),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return true;
      }),
    );
    if (!acquired) return false;
    _owner = owner;
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await _renew();
      } on Object {
        // A temporarily busy DB is retried by the next heartbeat.
      }
    });
    try {
      await reload();
      return true;
    } on Object {
      await release();
      rethrow;
    }
  }

  Future<void> _renew() async {
    final owner = _owner;
    if (owner == null) return;
    await _retryBusy(
      () => db.transaction((tx) async {
        final rows = await tx.query(
          'state',
          where: 'key = ?',
          whereArgs: ['lease'],
        );
        if (rows.isEmpty ||
            (jsonDecode(rows.single['value'] as String) as Map)['owner'] !=
                owner) {
          return;
        }
        await tx.update(
          'state',
          {
            'value': jsonEncode({
              'owner': owner,
              'expires': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 3))
                  .toIso8601String(),
            }),
          },
          where: 'key = ?',
          whereArgs: ['lease'],
        );
      }),
    );
  }

  Future<DateTime?> get lastAttempt async {
    final rows = await db.query(
      'state',
      where: 'key = ?',
      whereArgs: ['attempt'],
    );
    return rows.isEmpty
        ? null
        : DateTime.tryParse(rows.single['value'] as String);
  }

  Future<void> recordAttempt(DateTime now) => db.insert('state', {
    'key': 'attempt',
    'value': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> release() async {
    _heartbeat?.cancel();
    final owner = _owner;
    _owner = null;
    if (owner != null) {
      await _retryBusy(
        () => db.transaction((tx) async {
          final rows = await tx.query(
            'state',
            where: 'key = ?',
            whereArgs: ['lease'],
          );
          if (rows.isNotEmpty &&
              (jsonDecode(rows.single['value'] as String) as Map)['owner'] ==
                  owner) {
            await tx.delete('state', where: 'key = ?', whereArgs: ['lease']);
          }
        }),
      );
    }
  }

  Future<void> close() async {
    await release();
    await db.close();
  }
}
