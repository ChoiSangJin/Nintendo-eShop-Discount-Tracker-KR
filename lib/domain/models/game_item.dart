import 'package:html/parser.dart' as html;
import 'genre_catalog.dart';

int? parsePrice(dynamic value) {
  if (value is num) return value.isFinite && value >= 0 ? value.round() : null;
  if (value is! String) return null;
  final normalized = value.replaceAll(',', '').replaceAll('원', '').trim();
  final amount = num.tryParse(normalized);
  return amount != null && amount.isFinite && amount >= 0
      ? amount.round()
      : null;
}

DateTime? parseDate(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

enum GamePlatform { switch1, switch2, unknown }

class GameItem {
  const GameItem({
    required this.id,
    required this.name,
    required this.originalName,
    this.bannerUrl,
    this.genres = const [],
    this.releaseDate,
    this.regularPrice,
    this.discountPrice,
    this.discountStart,
    this.discountEnd,
    this.priceCheckedAt,
    this.hardware = 'Nintendo Switch',
    this.popularityRank,
  });

  final String id;
  final String name;
  final String originalName;
  final String? bannerUrl;
  final List<String> genres;
  final DateTime? releaseDate;
  final int? regularPrice;
  final int? discountPrice;
  final DateTime? discountStart;
  final DateTime? discountEnd;
  final DateTime? priceCheckedAt;
  final String hardware;
  final int? popularityRank;

  GamePlatform get platform => switch (hardware.trim().toLowerCase()) {
    'nintendo switch' => GamePlatform.switch1,
    'nintendo switch 2' || 'nintendo switch 2 edition' => GamePlatform.switch2,
    _ => GamePlatform.unknown,
  };

  String get platformLabel => switch (platform) {
    GamePlatform.switch1 => 'Switch 1',
    GamePlatform.switch2 =>
      hardware.trim().toLowerCase().endsWith('edition')
          ? 'Switch 2 Edition'
          : 'Switch 2',
    GamePlatform.unknown => hardware.trim().isEmpty ? '기종 미확인' : hardware,
  };

  static int calculateDiscountRate(int? regular, int? discount) {
    if (regular == null ||
        discount == null ||
        regular <= 0 ||
        discount >= regular) {
      return 0;
    }
    return (((regular - discount) / regular) * 100).round();
  }

  bool saleActiveAt(DateTime now) =>
      discountPrice != null &&
      regularPrice != null &&
      discountPrice! < regularPrice! &&
      (discountStart == null || !now.isBefore(discountStart!)) &&
      (discountEnd == null || now.isBefore(discountEnd!));

  int? priceAt(DateTime now) =>
      saleActiveAt(now) ? discountPrice : regularPrice;
  int discountRateAt(DateTime now) => saleActiveAt(now)
      ? calculateDiscountRate(regularPrice, discountPrice)
      : 0;

  GameItem withName(String title) => GameItem(
    id: id,
    name: title,
    originalName: originalName,
    bannerUrl: bannerUrl,
    genres: genres,
    releaseDate: releaseDate,
    regularPrice: regularPrice,
    discountPrice: discountPrice,
    discountStart: discountStart,
    discountEnd: discountEnd,
    priceCheckedAt: priceCheckedAt,
    hardware: hardware,
    popularityRank: popularityRank,
  );

  GameItem withPopularityRank(int? rank) =>
      GameItem.fromJson({...toJson(), 'popularityRank': rank});

  GameItem withPrice(Map<String, dynamic>? json, DateTime checkedAt) {
    final regular = json?['regular_price'];
    final discount = json?['discount_price'];
    return GameItem(
      id: id,
      name: name,
      originalName: originalName,
      bannerUrl: bannerUrl,
      genres: genres,
      releaseDate: releaseDate,
      regularPrice: regular is Map
          ? parsePrice(regular['raw_value'] ?? regular['amount'])
          : null,
      discountPrice: discount is Map
          ? parsePrice(discount['raw_value'] ?? discount['amount'])
          : null,
      discountStart: discount is Map
          ? parseDate(discount['start_datetime'])
          : null,
      discountEnd: discount is Map ? parseDate(discount['end_datetime']) : null,
      priceCheckedAt: json == null ? null : checkedAt,
      hardware: hardware,
      popularityRank: popularityRank,
    );
  }

  factory GameItem.fromMetadata(Map<String, dynamic> json) {
    final rawGenres = json['genres'];
    final title = (json['formal_name'] ?? json['name'] ?? '제목 정보 없음')
        .toString();
    final image = json['hero_banner_url'] ?? json['thumbnail_url'];
    return GameItem(
      id: json['id'].toString(),
      name: title,
      originalName: title,
      bannerUrl: image is String && Uri.tryParse(image)?.scheme == 'https'
          ? image
          : null,
      genres: rawGenres is List
          ? rawGenres
                .map(
                  (e) => e is Map ? (e['name'] ?? '').toString() : e.toString(),
                )
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      releaseDate: parseDate(json['release_date_on_eshop']),
      hardware: json['hardware']?.toString() ?? 'Nintendo Switch',
    );
  }

  factory GameItem.fromKoreanCatalog(Map<String, dynamic> json) {
    final title =
        html
            .parseFragment(json['title']?.toString() ?? '제목 정보 없음')
            .text
            ?.trim() ??
        '';
    final image = json['imageHero'];
    final metadata = GameItem.fromMetadata({
      'id': json['nsuid'],
      'hardware': json['hardwareCategory'],
      'formal_name': title,
      'hero_banner_url': image is Map ? image['url'] : null,
      'genres': json['genres'] ?? json['genre'] ?? knownGenres(title),
      'release_date_on_eshop':
          json['releaseDateDownload'] ?? json['releaseDate'],
    });
    return metadata;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'originalName': originalName,
    'bannerUrl': bannerUrl,
    'genres': genres,
    'releaseDate': releaseDate?.toIso8601String(),
    'regularPrice': regularPrice,
    'discountPrice': discountPrice,
    'discountStart': discountStart?.toIso8601String(),
    'discountEnd': discountEnd?.toIso8601String(),
    'priceCheckedAt': priceCheckedAt?.toIso8601String(),
    'hardware': hardware,
    'popularityRank': popularityRank,
  };

  factory GameItem.fromJson(Map<String, dynamic> json) => GameItem(
    id: json['id'] as String,
    name: json['name'] as String,
    originalName: (json['originalName'] ?? json['name']) as String,
    bannerUrl: json['bannerUrl'] as String?,
    genres: List<String>.from(json['genres'] as List? ?? []),
    releaseDate: parseDate(json['releaseDate']),
    regularPrice: parsePrice(json['regularPrice']),
    discountPrice: parsePrice(json['discountPrice']),
    discountStart: parseDate(json['discountStart']),
    discountEnd: parseDate(json['discountEnd']),
    priceCheckedAt: parseDate(json['priceCheckedAt']),
    hardware: json['hardware']?.toString() ?? 'Nintendo Switch',
    popularityRank: (json['popularityRank'] as num?)?.toInt(),
  );
}
