import 'dart:math';
import 'package:dio/dio.dart';
import '../../domain/models/game_item.dart';
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
