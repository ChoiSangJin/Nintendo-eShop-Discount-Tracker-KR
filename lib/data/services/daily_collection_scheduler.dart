import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import '../datasources/local_store.dart';
import '../../presentation/controllers/game_list_controller.dart';
import 'daily_collection_policy.dart';

const _task = 'kr.daily.catalog.v1';

@pragma('vm:entry-point')
void dailyCollectionDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _task) return true;
    WidgetsFlutterBinding.ensureInitialized();
    HiveLocalStore? store;
    ProviderContainer? container;
    try {
      // Enqueue tomorrow before collecting; interruption cannot break the chain.
      await DailyCollectionScheduler.scheduleNext();
      store = await HiveLocalStore.open(background: true);
      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      final controller = container.read(gameListProvider.notifier);
      await controller
          .refresh(force: false)
          .timeout(const Duration(minutes: 8));
      final state = container.read(gameListProvider);
      // Retry incomplete metadata, price failures, or a busy foreground engine.
      return state.complete &&
          state.error == null &&
          state.storageError == null &&
          !DailyCollectionPolicy.isDue(
            DateTime.now().toUtc(),
            store.catalogFetchedAt,
            store.cachedAt,
          );
    } on Object {
      return false;
    } finally {
      // Disposing closes Dio and stops a timed-out scan before its DB is closed.
      container?.dispose();
      await store?.close();
    }
  });
}

class DailyCollectionScheduler {
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(dailyCollectionDispatcher);
    await scheduleNext();
  }

  static Future<void> scheduleNext({DateTime? at}) async {
    final now = (at ?? DateTime.now()).toUtc();
    final next = DailyCollectionPolicy.nextRun(now);
    await Workmanager().registerOneOffTask(
      '$_task.${next.millisecondsSinceEpoch}',
      _task,
      initialDelay: next.difference(now),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: DailyCollectionPolicy.retryDelay,
    );
  }
}
