import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:switch_sale_tracker/data/datasources/local_store.dart';
import 'package:switch_sale_tracker/data/datasources/korean_title_resolver.dart';
import 'package:switch_sale_tracker/data/repositories/game_repository.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'live incremental catalog retains previous games and persists observed new games independently of prices',
    () async {
      final cert = Platform.environment['CODEX_PROXY_CERT'];
      if (cert != null) {
        SecurityContext.defaultContext.setTrustedCertificates(cert);
      }
      final proxy = Platform.environment['HTTPS_PROXY'];
      if (proxy != null) HttpOverrides.global = _Proxy(Uri.parse(proxy));
      final dir = await Directory.systemTemp.createTemp('incremental-live-');
      Hive.init(dir.path);
      final store = HiveLocalStore(
        await Hive.openBox('cache'),
        await Hive.openBox('favorites'),
        await Hive.openBox('titles'),
      );
      await store.seedCatalog();
      final oldIds = store.readGames().map((g) => g.id).toSet();
      final oldFullAt = store.catalogFetchedAt;
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      var metadataRequests = 0, priceRequests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.uri.path == '/kr/api/software') metadataRequests++;
            if (o.uri.path == '/v1/price') priceRequests++;
            h.next(o);
          },
        ),
      );
      final controller = GameListController(
        NintendoGameRepository(dio, KoreanTitleResolver(dio, store)),
        store,
      );
      final watch = Stopwatch()..start();
      var lastLog = -20;
      controller.addListener((s) {
        if (watch.elapsed.inSeconds - lastLog >= 20) {
          stdout.writeln(
            '${watch.elapsed.inSeconds}s ${s.progress?.label} ${s.progress?.completed}/${s.progress?.total}; visible=${s.games.length}',
          );
          lastLog = watch.elapsed.inSeconds;
        }
      }, fireImmediately: false);
      try {
        await controller.refresh(fullCatalog: true);
        final saved = store.readGames();
        final ids = saved.map((g) => g.id).toSet();
        final newIds = ids.difference(oldIds);
        expect(oldIds, isNotEmpty);
        expect(ids.containsAll(oldIds), isTrue);
        expect(newIds, isNotEmpty);
        expect(saved.map((g) => g.id).toSet().length, saved.length);
        expect(store.catalogCheckedAt, isNotNull);
        if (store.catalogRefreshFailed) {
          expect(store.catalogFetchedAt, oldFullAt);
        }
        stdout.writeln(
          'LIVE RESULT old=${oldIds.length} saved=${saved.length} new=${newIds.length} metadataRequests=$metadataRequests priceRequests=$priceRequests partial=${store.catalogRefreshFailed} priceUpdated=${store.cachedAt} priceError=${controller.state.error}',
        );
        for (final g in saved.where((g) => newIds.contains(g.id)).take(5)) {
          stdout.writeln('NEW ${g.id} ${g.name}');
        }
      } finally {
        controller.dispose();
        dio.close(force: true);
        await Hive.close();
        await dir.delete(recursive: true);
        HttpOverrides.global = null;
      }
    },
    skip: Platform.environment['RUN_INCREMENTAL_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

class _Proxy extends HttpOverrides {
  _Proxy(this.uri);
  final Uri uri;
  @override
  HttpClient createHttpClient(SecurityContext? c) =>
      super.createHttpClient(c)
        ..findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
}
