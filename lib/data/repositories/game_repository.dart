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
  NintendoGameRepository(
    this.dio,
    this.titles, {
    this.priceRequestInterval = const Duration(milliseconds: 250),
  });
  final Dio dio;
  final KoreanTitleResolver titles;
  final Duration priceRequestInterval;
  DateTime _nextPriceRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _waitForPriceSlot() async {
    final now = DateTime.now();
    final slot = _nextPriceRequest.isAfter(now) ? _nextPriceRequest : now;
    _nextPriceRequest = slot.add(priceRequestInterval);
    if (slot.isAfter(now)) await Future<void>.delayed(slot.difference(now));
  }

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
    return refreshPrices(
      await fetchMetadata(onProgress: onProgress),
      onProgress: onProgress,
    );
  }

  Future<List<GameItem>> fetchMetadata({ProgressCallback? onProgress}) async {
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
    final boundaryPages = <num>{};
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
        if (records.containsKey(item['sys']['id'])) boundaryPages.add(number);
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
      var next = 0;
      var failed = false;
      Future<void> worker() async {
        try {
          while (next < numbers.length &&
              !failed &&
              !(finishEarly && records.length == total)) {
            final number = numbers[next++];
            accept(await page(number, oldest: oldest), number);
          }
        } on Object {
          failed = true;
          rethrow;
        }
      }

      await Future.wait(List.generate(min(4, numbers.length), (_) => worker()));
    }

    await scan(List.generate(pages - 1, (i) => i + 2), finishEarly: false);
    // Repair the boundaries that actually overlapped before rescanning the
    // entire catalog in reverse. Keep the full coverage checks below.
    if (records.length < total && boundaryPages.length <= 4) {
      final repairs = {
        for (final number in boundaryPages)
          for (final shift in [-0.5, 0.5])
            if (number + shift >= 1 &&
                (number + shift - 1) * catalogPageSize < total)
              number + shift,
      }.toList()..sort();
      await scan(repairs);
    }
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
    return games.values.toList();
  }

  static final _rankingFile = RegExp(
    r'^/kr/switch/ranking/ranking_(\d{4})_(1st|full)(_switch2)?\.html$',
  );

  static Uri rankingUrl(String href, Uri base) {
    final uri = base.resolve(href);
    if (uri.scheme != 'https' ||
        uri.host != 'www.nintendo.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_rankingFile.hasMatch(uri.path)) {
      throw const FormatException('한국 공식 순위 경로를 확인할 수 없습니다.');
    }
    return uri;
  }

  @override
  Future<PopularityIndex> fetchPopularity() async {
    Future<String> read(Uri uri) async =>
        (await dio.get<String>(
          uri.toString(),
          options: Options(responseType: ResponseType.plain),
        )).data ??
        '';
    final entry = Uri.parse('https://www.nintendo.com/kr/switch/ranking/');
    final landing = await read(entry);
    final redirect = RegExp(
      r'''window\.location\.href\s*=\s*['"]([^'"]+)['"]''',
    ).firstMatch(landing);
    if (redirect == null) {
      throw const FormatException('한국 공식 최신 순위 경로가 바뀌었습니다.');
    }
    final firstUrl = rankingUrl(redirect[1]!, entry);
    if (firstUrl.path.endsWith('_switch2.html')) {
      throw const FormatException('한국 공식 기종별 순위 경로를 확인할 수 없습니다.');
    }
    final firstBody = await read(firstUrl);
    final first = parsePopularity(firstBody, sourceUrl: firstUrl);
    final secondPath = firstUrl.path.replaceFirst('.html', '_switch2.html');
    final secondLinks = html
        .parse(firstBody)
        .querySelectorAll('#featureListRanking__tabSwitcherArea a[href]');
    final secondUrl = secondLinks
        .map((a) => firstUrl.resolve(a.attributes['href']!))
        .where((uri) => uri.host == firstUrl.host && uri.path == secondPath)
        .firstOrNull;
    if (secondUrl == null) {
      throw const FormatException('한국 공식 Switch 2 순위 링크를 확인할 수 없습니다.');
    }
    final second = parsePopularity(
      await read(rankingUrl(secondUrl.toString(), firstUrl)),
      sourceUrl: secondUrl,
    );
    if (first.source != second.source ||
        first.byId.keys.any(second.byId.containsKey)) {
      throw const FormatException('한국 공식 기종별 순위의 집계 기간 또는 상품 ID가 일치하지 않습니다.');
    }
    return PopularityIndex(
      {...first.byId, ...second.byId},
      source: first.source,
      entries: [...first.entries, ...second.entries],
    );
  }

  static PopularityIndex parsePopularity(
    String body, {
    required Uri sourceUrl,
  }) {
    final uri = rankingUrl(sourceUrl.toString(), sourceUrl);
    final period = _rankingFile.firstMatch(uri.path)!;
    final source = 'kr:${period[1]}:${period[2]}';
    final switch2 = period[3] != null;
    final platform = switch2 ? GamePlatform.switch2 : GamePlatform.switch1;
    final document = html.parse(body);
    final heading =
        document
            .querySelector('#featureListRanking__headlineTextArea')
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ') ??
        '';
    if (!heading.contains('Nintendo Switch') ||
        heading.contains('Nintendo Switch 2 ') != switch2 ||
        !heading.contains('${PopularityIndex.periodLabel(source)} 다운로드 랭킹') ||
        !heading.contains('유료')) {
      throw const FormatException('한국 공식 순위의 집계 기간과 대상을 확인할 수 없습니다.');
    }
    final entries = <PopularityEntry>[];
    for (final card in document.querySelectorAll(
      '#featureListRanking [data-rank]',
    )) {
      final rank = int.tryParse(card.attributes['data-rank'] ?? '');
      final title = card.querySelector('.tit')?.text.trim() ?? '';
      final link = Uri.tryParse(
        card.querySelector('a[href]')?.attributes['href'] ?? '',
      );
      if (rank == null ||
          rank <= 0 ||
          title.isEmpty ||
          link == null ||
          link.scheme != 'https' ||
          link.host != 'store.nintendo.co.kr' ||
          link.userInfo.isNotEmpty ||
          link.pathSegments.length != 1 ||
          !isStoreId(link.pathSegments.single)) {
        throw const FormatException('한국 공식 순위 항목을 확인할 수 없습니다.');
      }
      entries.add(
        PopularityEntry(link.pathSegments.single, title, platform, rank),
      );
    }
    entries.sort((a, b) => a.rank.compareTo(b.rank));
    if (entries.isEmpty ||
        entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('한국 공식 순위가 비어 있거나 중복되었습니다.');
    }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].rank != i + 1) {
        throw const FormatException('한국 공식 순위에 누락 또는 중복이 있습니다.');
      }
    }
    return PopularityIndex(
      {for (final e in entries) e.id: e.rank},
      source: source,
      entries: entries,
    );
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
    var next = 0;
    var failed = false;
    onProgress?.call(CatalogProgress('전체 게임 가격 확인 중', 0, ids.length));
    Future<void> worker() async {
      try {
        while (next < ids.length && !failed) {
          final start = next;
          next += pageSize;
          final batch = ids.sublist(start, min(start + pageSize, ids.length));
          await _waitForPriceSlot();
          if (failed) return;
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
          for (final entry in raw.cast<Map>()) {
            prices[entry['title_id'].toString()] = Map<String, dynamic>.from(
              entry,
            );
          }
          completed += batch.length;
          onProgress?.call(
            CatalogProgress('전체 게임 가격 확인 중', completed, ids.length),
          );
        }
      } on Object {
        failed = true;
        rethrow;
      }
    }

    await Future.wait(
      List.generate(min(4, (ids.length / pageSize).ceil()), (_) => worker()),
    );
    final now = DateTime.now().toUtc();
    return games.map((game) => game.withPrice(prices[game.id], now)).toList();
  }
}
