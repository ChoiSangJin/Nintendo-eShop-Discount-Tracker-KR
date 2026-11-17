import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:switch_sale_tracker/data/services/daily_collection_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'package:switch_sale_tracker/data/services/catalog_database.dart';
import 'package:switch_sale_tracker/data/services/daily_collection_policy.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'scheduler targets next Korean 01:00 and preserves an existing reservation',
    () async {
      Workmanager(); // Initialize the facade before replacing its platform.
      final original = WorkmanagerPlatform.instance;
      final platform = _SchedulerPlatform();
      WorkmanagerPlatform.instance = platform;
      addTearDown(() => WorkmanagerPlatform.instance = original);
      final at = DateTime.parse('2026-11-17T00:30:00+09:00');
      await DailyCollectionScheduler.scheduleNext(at: at);
      await DailyCollectionScheduler.scheduleNext(
        at: at.add(const Duration(minutes: 10)),
      );
      expect(platform.names.toSet(), hasLength(1));
      expect(platform.delays, [
        const Duration(minutes: 30),
        const Duration(minutes: 20),
      ]);
      expect(platform.policy, ExistingWorkPolicy.keep);
      expect(platform.network, NetworkType.connected);
      await DailyCollectionScheduler.scheduleNext(
        at: at.add(const Duration(hours: 1)),
      );
      expect(platform.names.toSet(), hasLength(2));
      expect(platform.delays.last, const Duration(hours: 23, minutes: 30));
    },
  );

  test(
    'Korean 01:00 boundary is independent of device timezone and month/year',
    () {
      final before = DateTime.parse('2026-11-17T00:59:59+09:00');
      final at = DateTime.parse('2026-11-17T01:00:00+09:00');
      expect(
        DailyCollectionPolicy.boundary(before),
        DateTime.utc(2026, 11, 15, 16),
      );
      expect(
        DailyCollectionPolicy.boundary(at),
        DateTime.utc(2026, 11, 16, 16),
      );
      expect(DailyCollectionPolicy.nextRun(at), DateTime.utc(2026, 11, 17, 16));
      expect(
        DailyCollectionPolicy.boundary(
          DateTime.parse('2027-01-01T00:30:00+09:00'),
        ),
        DateTime.utc(2026, 12, 30, 16),
      );
      expect(DailyCollectionPolicy.isDue(at, before, before), isTrue);
      expect(DailyCollectionPolicy.isDue(at, at, at), isFalse);
      expect(DailyCollectionPolicy.isDue(at, null, at), isTrue);
      expect(DailyCollectionPolicy.isDue(before, at, at), isTrue);
    },
  );

  test(
    'separate engines share snapshots and exclude simultaneous collectors; expired leases recover',
    () async {
      final dir = await Directory.systemTemp.createTemp('daily-shared-');
      final path = '${dir.path}/shared.db';
      final a = await CatalogDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      final b = await CatalogDatabase.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      try {
        final now = DateTime.now().toUtc();
        final results = await Future.wait([a.acquire(now), b.acquire(now)]);
        expect(results.where((v) => v), hasLength(1));
        final winner = results.first ? a : b;
        final other = results.first ? b : a;
        await winner.save({'games': [], 'version': 7});
        await winner.recordAttempt(now);
        expect(await other.lastAttempt, now);
        await winner.release();
        expect(await other.acquire(now), isTrue);
        expect(other.snapshot!['version'], 7);
        await other.release();
        // A killed worker cannot hold the app's refresh lock forever.
        expect(
          await a.acquire(now.subtract(const Duration(minutes: 4))),
          isTrue,
        );
        expect(await b.acquire(now), isTrue);
        await a
            .release(); // Old owner cannot release the replacement owner's lease.
        expect(await a.acquire(now), isFalse);
      } finally {
        await a.close();
        await b.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'foreground imports background results without another scan and keeps favorites',
    () async {
      final dir = await Directory.systemTemp.createTemp('daily-import-');
      Hive.init(dir.path);
      final db = await CatalogDatabase.open(
        path: '${dir.path}/shared.db',
        factory: databaseFactoryFfi,
      );
      final worker = await CatalogDatabase.open(
        path: '${dir.path}/shared.db',
        factory: databaseFactoryFfi,
      );
      final store = HiveLocalStore(
        await Hive.openBox('cache'),
        await Hive.openBox('favorites'),
        await Hive.openBox('titles'),
        database: db,
      );
      try {
        final now = DateTime.now().toUtc();
        await store.saveGames([
          exampleGame(name: '이전 목록'),
        ], now.subtract(const Duration(days: 2)));
        await store.saveFavorite(exampleGame(name: '내 관심 게임'));
        final repo = FakeRepository();
        final controller = GameListController(repo, store);
        await worker.reload();
        await worker.save({
          ...worker.snapshot!,
          'games': [exampleGame(name: '백그라운드 갱신').toJson()],
          'updated_at': now.toIso8601String(),
          'catalog_at': now.toIso8601String(),
          'catalog_checked_at': now.toIso8601String(),
        });
        await controller.refresh(force: false);
        expect(repo.catalogCalls, 0);
        expect(controller.state.games.single.name, '백그라운드 갱신');
        expect(store.readFavorites(), hasLength(1));
        controller.dispose();
        await db.recordAttempt(now);
        // A partial catalog does not satisfy the daily collection; throttle automatic retries.
        await store.saveGames(
          [exampleGame()],
          now,
          catalogAt: now.subtract(const Duration(days: 2)),
          catalogRefreshFailed: true,
        );
        final retry = GameListController(repo, store);
        await retry.refresh(force: false);
        expect(repo.catalogCalls, 0);
        await retry.refresh(fullCatalog: true);
        expect(repo.metadataReuse, [
          false,
        ]); // Manual retry bypasses the throttle.
        retry.dispose();
      } finally {
        await store.close();
        await worker.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

class _SchedulerPlatform extends WorkmanagerPlatform {
  final names = <String>[];
  final delays = <Duration?>[];
  ExistingWorkPolicy? policy;
  NetworkType? network;
  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    names.add(uniqueName);
    delays.add(initialDelay);
    policy = existingWorkPolicy;
    network = constraints?.networkType;
  }
}
