import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  test('prices distinguish unknown from free and reject invalid amounts', () {
    expect(parsePrice('74,800원'), 74800);
    expect(parsePrice('0'), 0);
    expect(parsePrice('-100'), isNull);
    expect(parsePrice('판매 중지'), isNull);
    expect(GameItem.calculateDiscountRate(74800, 52360), 30);
    expect(GameItem.calculateDiscountRate(0, 0), 0);
  });
  test(
    'discount expiry and future sales never show a misleading sale price',
    () {
      final now = DateTime.utc(2026, 10, 8);
      final expired = exampleGame(end: now);
      expect(expired.saleActiveAt(now), isFalse);
      expect(expired.priceAt(now), 50000);
      expect(expired.discountRateAt(now), 0);
      final upcoming = GameItem(
        id: '1',
        name: '게임',
        originalName: '게임',
        regularPrice: 1000,
        discountPrice: 500,
        discountStart: now.add(const Duration(days: 1)),
      );
      expect(upcoming.priceAt(now), 1000);
    },
  );
  test('metadata and snapshots round trip Korean names and dates', () {
    final game = GameItem.fromMetadata({
      'id': 70010000000001,
      'formal_name': '젤다의 전설',
      'genres': [
        {'name': '어드벤처'},
        'RPG',
      ],
      'release_date_on_eshop': '2023-05-12',
      'hero_banner_url': 'https://example.com/banner.jpg',
    });
    final restored = GameItem.fromJson(game.toJson());
    expect(restored.id, '70010000000001');
    expect(restored.name, '젤다의 전설');
    expect(restored.genres, ['어드벤처', 'RPG']);
    expect(restored.releaseDate, DateTime(2023, 5, 12));
    expect(restored.priceAt(DateTime.now()), isNull);
  });
  test('Korean search, genre aliases, sorting and unknown prices', () {
    final items = [
      exampleGame(
        id: '1',
        name: '모험',
        discount: 40000,
        genres: ['Adventure'],
        releaseDate: DateTime(2025),
      ),
      exampleGame(
        id: '2',
        name: '용사',
        discount: 10000,
        genres: ['RPG'],
        releaseDate: DateTime(2026),
      ),
      exampleGame(id: '3', name: '가격 미확인', regular: null, discount: null),
    ];
    final now = DateTime.now();
    expect(
      filterAndSortGames(
        items,
        genre: '어드벤처',
        query: '',
        sort: GameSort.price,
        now: now,
      ).single.id,
      '1',
    );
    expect(
      filterAndSortGames(
        items,
        genre: '전체',
        query: '용',
        sort: GameSort.newest,
        now: now,
      ).single.id,
      '2',
    );
    expect(
      filterAndSortGames(
        items,
        genre: '전체',
        query: '',
        sort: GameSort.price,
        now: now,
      ).map((g) => g.id),
      ['2', '1', '3'],
    );
    expect(
      filterAndSortGames(
        items,
        genre: '전체',
        query: '',
        sort: GameSort.discount,
        now: now,
      ).first.id,
      '2',
    );
  });
}
