import 'dart:math';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../../domain/models/game_item.dart';
import '../../domain/models/popularity_index.dart';
import '../datasources/korean_title_resolver.dart';

class GamePage {
  const GamePage(
    this.games,
    this.total,
    this.nextOffset, {
    this.catalogFallback = false,
  });
  final List<GameItem> games;
  final int total;
  final int nextOffset;
  final bool catalogFallback;
}

abstract class GameRepository {
  Future<GamePage> fetchPage(int offset);
  Future<GamePage> searchPage(String query, int offset);
  Future<PopularityIndex> fetchPopularity();
  Future<List<GameItem>> fetchPopularGames(PopularityIndex popularity);
  Future<List<GameItem>> refreshPrices(List<GameItem> games);
  Future<List<GameItem>> localize(List<GameItem> games);
}

class NintendoGameRepository implements GameRepository {
  NintendoGameRepository(this.dio, this.titles);
  final Dio dio;
  final KoreanTitleResolver titles;
  static const pageSize = 30;
  static const catalogPageSize = 24;
  bool _legacyUnavailable = false;

  @override
  Future<GamePage> searchPage(String query, int offset) async {
    // This endpoint searches the whole official KR catalog, including titles
    // that are not on sale. Preserve its matches (e.g. Pokémon aliases).
    final response = await dio.get<Map<String, dynamic>>(
      'https://www.nintendo.com/kr/api/search',
      queryParameters: {
        'k': query.trim(),
        'directory': 'software',
        'size': catalogPageSize,
        'p': offset ~/ catalogPageSize + 1,
      },
    );
    final data = response.data;
    if (data == null || data['items'] is! List || data['total'] is! num) {
      throw const FormatException('한국 게임 검색 응답을 확인할 수 없습니다.');
    }
    final items = data['items'] as List;
    final games = items
        .whereType<Map>()
        .where(
          (item) =>
              RegExp(r'^\d{14}$').hasMatch(item['nsuid']?.toString() ?? ''),
        )
        .map(
          (item) => GameItem.fromKoreanCatalog(Map<String, dynamic>.from(item)),
        )
        .toList();
    return GamePage(
      await refreshPrices(games),
      (data['total'] as num).toInt(),
      offset + items.length,
      catalogFallback: true,
    );
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
  Future<List<GameItem>> fetchPopularGames(PopularityIndex popularity) async {
    final metadata = <String, GameItem>{};
    final seen = <String>{};
    final entries = popularity.entries
        .where((e) => seen.add(PopularityIndex.key(e.title, e.hardware)))
        .toList();
    // Only requested when the user selects popularity. Resolve the US list
    // through KR's catalog, never use US prices or assume regional IDs match.
    // Bound concurrency; price all resolved IDs in batches of at most 30.
    for (var start = 0; start < entries.length; start += 4) {
      final batch = entries.sublist(start, min(start + 4, entries.length));
      final results = await Future.wait(
        batch.map((entry) async {
          final response = await dio.get<Map<String, dynamic>>(
            'https://www.nintendo.com/kr/api/search',
            queryParameters: {
              'k': PopularityIndex.koreanSearchTerm(entry.title),
              'directory': 'software',
              'size': catalogPageSize,
              'p': 1,
            },
          );
          final items = response.data?['items'];
          if (items is! List) {
            throw const FormatException('한국 인기 게임 확인에 실패했습니다.');
          }
          return items
              .whereType<Map>()
              .where(
                (item) => RegExp(
                  r'^\d{14}$',
                ).hasMatch(item['nsuid']?.toString() ?? ''),
              )
              .map(
                (item) =>
                    GameItem.fromKoreanCatalog(Map<String, dynamic>.from(item)),
              )
              .where(
                (game) =>
                    game.hardware == entry.hardware &&
                    popularity.rankFor(game) != null,
              )
              .toList();
        }),
      );
      for (final games in results) {
        for (final game in games) {
          metadata[game.id] = game;
        }
      }
    }
    final priced = await refreshPrices(metadata.values.toList());
    return priced
        .where((g) => g.saleActiveAt(DateTime.now().toUtc()))
        .map((g) => g.withPopularityRank(popularity.rankFor(g)))
        .toList();
  }

  @override
  Future<GamePage> fetchPage(int offset) async {
    if (_legacyUnavailable) return _fetchCatalogSales(offset);
    try {
      return await _fetchLegacySales(offset);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404 &&
          error.response?.statusCode != 410) {
        rethrow;
      }
      _legacyUnavailable = true;
      return _fetchCatalogSales(offset);
    }
  }

  Future<GamePage> _fetchCatalogSales(int offset) async {
    final sales = <String, GameItem>{};
    var cursor = offset;
    var total = offset + 1;
    // The old eShop search API was retired. The public Korean catalog supplies
    // official localized titles; the KR price service identifies actual sales.
    // Bound each foreground call to four catalog pages. Preserve raw offsets,
    // including invalid NSUIDs, so no games are silently skipped.
    for (var round = 0; round < 4 && cursor < total; round++) {
      final response = await dio.get<Map<String, dynamic>>(
        'https://www.nintendo.com/kr/api/software',
        queryParameters: {
          'sftab': 'all',
          'spage': cursor ~/ catalogPageSize + 1,
        },
      );
      final data = response.data;
      if (data == null || data['items'] is! List || data['total'] is! num) {
        throw const FormatException('한국 공식 카탈로그 응답 형식을 확인할 수 없습니다.');
      }
      final items = data['items'] as List;
      total = (data['total'] as num).toInt();
      if (items.isEmpty) {
        cursor = total;
        break;
      }
      final games = items
          .whereType<Map>()
          .where(
            (item) =>
                RegExp(r'^\d{14}$').hasMatch(item['nsuid']?.toString() ?? ''),
          )
          .map(
            (item) =>
                GameItem.fromKoreanCatalog(Map<String, dynamic>.from(item)),
          )
          .toList();
      final priced = await refreshPrices(games);
      final now = DateTime.now().toUtc();
      for (final game in priced) {
        if (game.saleActiveAt(now)) sales[game.id] = game;
      }
      cursor += items.length;
      if (sales.length >= pageSize) break;
    }
    return GamePage(
      sales.values.toList(),
      total,
      cursor,
      catalogFallback: true,
    );
  }

  Future<GamePage> _fetchLegacySales(int offset) async {
    final response = await dio.get<Map<String, dynamic>>(
      'https://ec.nintendo.com/api/KR/ko/search/sales',
      queryParameters: {'count': pageSize, 'offset': offset},
    );
    final data = response.data;
    if (data == null || data['contents'] is! List || data['total'] is! num) {
      throw const FormatException('한국 eShop 응답 형식을 확인할 수 없습니다.');
    }
    final contents = data['contents'] as List;
    final games = <GameItem>[];
    for (final item in contents) {
      if (item is Map) {
        final id = item['id']?.toString() ?? '';
        if (RegExp(r'^\d{14}$').hasMatch(id)) {
          games.add(GameItem.fromMetadata(Map<String, dynamic>.from(item)));
        }
      }
    }
    // Offset follows raw records, not filtered or deduplicated records.
    final priced = await refreshPrices(games);
    return GamePage(
      priced,
      (data['total'] as num).toInt(),
      offset + contents.length,
    );
  }

  @override
  Future<List<GameItem>> refreshPrices(List<GameItem> games) async {
    if (games.isEmpty) return [];
    final prices = <String, Map<String, dynamic>>{};
    final ids = games.map((game) => game.id).toSet().toList();
    for (var i = 0; i < ids.length; i += pageSize) {
      final batch = ids.sublist(i, min(i + pageSize, ids.length));
      final response = await dio.get<Map<String, dynamic>>(
        'https://api.ec.nintendo.com/v1/price',
        queryParameters: {
          'country': 'KR',
          'lang': 'ko',
          'ids': batch.join(','),
        },
      );
      final raw = response.data?['prices'];
      if (raw is! List) throw const FormatException('가격 응답 형식을 확인할 수 없습니다.');
      for (final entry in raw) {
        if (entry is Map) {
          prices[entry['title_id'].toString()] = Map<String, dynamic>.from(
            entry,
          );
        }
      }
    }
    final now = DateTime.now().toUtc();
    return games.map((game) => game.withPrice(prices[game.id], now)).toList();
  }

  @override
  Future<List<GameItem>> localize(List<GameItem> games) async {
    final result = <GameItem>[];
    // Price requests stay batched. Optional, cached storefront title lookups
    // run separately with bounded concurrency, after the list is visible.
    for (var i = 0; i < games.length; i += 4) {
      final batch = games.sublist(i, min(i + 4, games.length));
      result.addAll(
        await Future.wait(
          batch.map(
            (game) async =>
                game.withName(await titles.resolve(game.id, game.name)),
          ),
        ),
      );
    }
    return result;
  }
}
