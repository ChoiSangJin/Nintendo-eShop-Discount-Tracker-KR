import 'dart:math';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../../domain/models/game_item.dart';
import '../../domain/models/popularity_index.dart';
import '../datasources/korean_title_resolver.dart';
import '../datasources/catalog_products.dart';

class CatalogProgress {
  const CatalogProgress(this.label, this.completed, this.total);
  final String label;
  final int completed;
  final int total;
}

typedef ProgressCallback = void Function(CatalogProgress progress);

abstract class GameRepository {
  Future<List<GameItem>> fetchCatalog({
    List<GameItem>? metadata,
    ProgressCallback? onProgress,
  });
  Future<PopularityIndex> fetchPopularity();
  Future<List<GameItem>> refreshPrices(
    List<GameItem> games, {
    ProgressCallback? onProgress,
  });
}

class NintendoGameRepository implements GameRepository {
  NintendoGameRepository(this.dio, this.titles);
  final Dio dio;
  final KoreanTitleResolver titles;
  static const pageSize = 30;
  static const catalogPageSize = 24;
  @override
  Future<List<GameItem>> fetchCatalog({
    List<GameItem>? metadata,
    ProgressCallback? onProgress,
  }) async {
    if (metadata != null && metadata.isNotEmpty) {
      return refreshPrices(metadata, onProgress: onProgress);
    }
    Future<Map<String, dynamic>> page(num number, {bool oldest = false}) async {
      final response = await dio.get<Map<String, dynamic>>(
        'https://www.nintendo.com/kr/api/software',
        queryParameters: {
          'sftab': 'all',
          'spage': number,
          if (oldest) 'sfsort': 'adate',
        },
      );
      final data = response.data;
      if (data == null ||
          data['items'] is! List ||
          data['total'] is! int ||
          (data['total'] as int) <= 0) {
        throw const FormatException('한국 전체 카탈로그를 확인할 수 없습니다.');
      }
      return data;
    }

    final first = await page(1);
    final total = first['total'] as int;
    final pages = (total / catalogPageSize).ceil();
    final records = <String, Map<String, dynamic>>{};
    void accept(Map<String, dynamic> data, num number) {
      final items = data['items'] as List;
      final offset = ((number - 1) * catalogPageSize).round();
      final expected = min(catalogPageSize, total - offset);
      if (data['total'] != total || items.length != expected) {
        throw const FormatException('전체 목록 확인 중 카탈로그가 변경되었습니다. 다시 시도해 주세요.');
      }
      for (final item in items) {
        if (item is! Map ||
            item['sys'] is! Map ||
            item['sys']['id'] is! String) {
          throw const FormatException('카탈로그 항목을 확인할 수 없습니다.');
        }
        records.putIfAbsent(
          item['sys']['id'] as String,
          () => Map<String, dynamic>.from(item),
        );
      }
      onProgress?.call(CatalogProgress('전체 게임 목록 확인 중', records.length, total));
    }

    accept(first, 1);
    Future<void> scan(
      List<num> numbers, {
      bool oldest = false,
      bool finishEarly = true,
    }) async {
      for (var start = 0; start < numbers.length; start += 4) {
        final batch = numbers.sublist(start, min(start + 4, numbers.length));
        final results = await Future.wait(
          batch.map((n) => page(n, oldest: oldest)),
        );
        for (var i = 0; i < results.length; i++) {
          accept(results[i], batch[i]);
        }
        if (records.length == total && finishEarly) return;
      }
    }

    await scan(List.generate(pages - 1, (i) => i + 2), finishEarly: false);
    // Nintendo sorts only by release date. Equal-date records can move across
    // offset boundaries even in an unchanged catalog. Scan the reverse order
    // and overlapping windows until every distinct official record is present.
    // Numeric page offsets are accepted by this API (0.5 page = 12 records).
    if (records.length < total) {
      await scan(List.generate(pages, (i) => i + 1), oldest: true);
    }
    for (final shift in [0.5, 0.25, 0.75]) {
      if (records.length == total) break;
      await scan(
        List.generate(
          ((total - 1) / catalogPageSize - shift).floor() + 1,
          (i) => i + 1 + shift,
        ),
      );
    }
    if (records.length != total) {
      throw const FormatException(
        '전체 게임 목록을 확보하지 못했습니다. 저장된 목록을 표시합니다. 잠시 후 다시 시도해 주세요.',
      );
    }
    final check = await page(1);
    if (check['total'] != total ||
        jsonEncode(check['items']) != jsonEncode(first['items'])) {
      throw const FormatException('전체 목록 확인 중 카탈로그가 변경되었습니다. 다시 시도해 주세요.');
    }
    final games = <String, GameItem>{};
    for (final record in records.values) {
      for (final product in expandCatalogRecord(record)) {
        final game = GameItem.fromKoreanCatalog(product);
        games.putIfAbsent(
          game.id,
          () => game.withName(titles.cachedName(game.id, game.name)),
        );
      }
    }
    if (games.isEmpty) throw const FormatException('유효한 게임 목록이 없습니다.');
    return refreshPrices(games.values.toList(), onProgress: onProgress);
  }

  @override
  Future<PopularityIndex> fetchPopularity() async {
    final response = await dio.get<String>(
      'https://www.nintendo.com/us/store/games/best-sellers/',
      options: Options(responseType: ResponseType.plain),
    );
    return parsePopularity(response.data ?? '');
  }

  static PopularityIndex parsePopularity(String body) {
    final script = html.parse(body).querySelector('script#__NEXT_DATA__')?.text;
    if (script == null) throw const FormatException('공식 인기 목록 형식이 바뀌었습니다.');
    final data = jsonDecode(script) as Map<String, dynamic>;
    final page = data['props']['pageProps']['page'];
    if (page['slug'] != '/games/best-sellers/') {
      throw const FormatException('공식 인기 목록을 확인할 수 없습니다.');
    }
    final items = page['content']['merchandisedGrid'] as List;
    final ranks = <String, int>{};
    final titles = <String, int>{};
    final entries = <PopularityEntry>[];
    for (var i = 0; i < items.length; i++) {
      final id = (items[i] as Map)['nsuid']?.toString() ?? '';
      if (RegExp(r'^\d{14}$').hasMatch(id)) {
        ranks.putIfAbsent(id, () => i + 1);
        final item = items[i] as Map;
        final name = item['name'];
        final hardware = item['platform'];
        if (name is String &&
            hardware is String &&
            name.isNotEmpty &&
            (hardware == 'Nintendo Switch' ||
                hardware == 'Nintendo Switch 2')) {
          titles.putIfAbsent(PopularityIndex.key(name, hardware), () => i + 1);
          entries.add(PopularityEntry(id, name, hardware, i + 1));
        }
      }
    }
    if (ranks.isEmpty) throw const FormatException('공식 인기 목록이 비어 있습니다.');
    return PopularityIndex(ranks, byTitle: titles, entries: entries);
  }

  @override
  Future<List<GameItem>> refreshPrices(
    List<GameItem> games, {
    ProgressCallback? onProgress,
  }) async {
    if (games.isEmpty) return [];
    final prices = <String, Map<String, dynamic>>{};
    final ids = games.map((game) => game.id).where(isStoreId).toSet().toList();
    var completed = 0;
    onProgress?.call(CatalogProgress('전체 게임 가격 확인 중', 0, ids.length));
    for (var start = 0; start < ids.length; start += pageSize * 4) {
      final batches = <List<String>>[];
      for (
        var i = start;
        i < min(start + pageSize * 4, ids.length);
        i += pageSize
      ) {
        batches.add(ids.sublist(i, min(i + pageSize, ids.length)));
      }
      final results = await Future.wait(
        batches.map((batch) async {
          final response = await dio.get<Map<String, dynamic>>(
            'https://api.ec.nintendo.com/v1/price',
            queryParameters: {
              'country': 'KR',
              'lang': 'ko',
              'ids': batch.join(','),
            },
          );
          final raw = response.data?['prices'];
          if (raw is! List || raw.any((e) => e is! Map)) {
            throw const FormatException('가격 응답 형식을 확인할 수 없습니다.');
          }
          completed += batch.length;
          onProgress?.call(
            CatalogProgress('전체 게임 가격 확인 중', completed, ids.length),
          );
          return raw;
        }),
      );
      for (final result in results) {
        for (final entry in result.cast<Map>()) {
          prices[entry['title_id'].toString()] = Map<String, dynamic>.from(
            entry,
          );
        }
      }
    }
    final now = DateTime.now().toUtc();
    return games.map((game) => game.withPrice(prices[game.id], now)).toList();
  }
}
