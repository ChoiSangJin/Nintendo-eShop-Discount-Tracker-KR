import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/presentation/controllers/game_list_controller.dart';
import 'support/fakes.dart';

void main() {
  test(
    'platform metadata keeps generations and editions distinct through storage',
    () {
      for (final hardware in [
        'Nintendo Switch 2',
        'Nintendo Switch 2 Edition',
      ]) {
        final restored = GameItem.fromJson(
          exampleGame(hardware: hardware).toJson(),
        );
        expect(restored.platform, GamePlatform.switch2);
        expect(restored.platformLabel, hardware.replaceFirst('Nintendo ', ''));
      }
      expect(
        exampleGame(name: 'Switch 2 이름의 Switch 1 게임').platform,
        GamePlatform.switch1,
      );
      final unknown = exampleGame(hardware: 'Unknown platform');
      expect(unknown.platform, GamePlatform.unknown);
      expect(unknown.platformLabel, 'Unknown platform');
    },
  );
  test(
    'discount decade/platform filters combine with genre, query and sorting',
    () {
      final now = DateTime.utc(2026, 10, 8);
      final games = [
        exampleGame(
          id: '1',
          name: '페르소나 50',
          regular: 20000,
          discount: 10000,
          genres: ['RPG'],
          hardware: 'Nintendo Switch 2',
        ),
        exampleGame(
          id: '2',
          name: 'Persona 59',
          regular: 20000,
          discount: 8200,
          genres: ['RPG'],
          hardware: 'Nintendo Switch 2 Edition',
        ),
        exampleGame(
          id: '3',
          name: '페르소나 60',
          regular: 20000,
          discount: 8000,
          genres: ['RPG'],
          hardware: 'Nintendo Switch 2',
        ),
        exampleGame(
          id: '4',
          name: '페르소나 50 Switch 1',
          regular: 20000,
          discount: 10000,
          genres: ['RPG'],
        ),
        exampleGame(
          id: '5',
          name: '다른 제목',
          regular: 20000,
          discount: 10000,
          genres: ['RPG'],
          hardware: 'Nintendo Switch 2',
        ),
        exampleGame(
          id: '6',
          name: '페르소나 장르',
          regular: 20000,
          discount: 10000,
          genres: ['Puzzle'],
          hardware: 'Nintendo Switch 2',
        ),
        exampleGame(
          id: '7',
          name: '페르소나 종료',
          regular: 20000,
          discount: 10000,
          end: now,
          genres: ['RPG'],
          hardware: 'Nintendo Switch 2',
        ),
        exampleGame(
          id: '8',
          name: '페르소나 미확인',
          regular: 20000,
          discount: 10000,
          genres: ['RPG'],
          hardware: 'Unknown platform',
        ),
      ];
      final filtered = filterAndSortGames(
        games,
        genre: 'RPG',
        query: 'Persona',
        sort: GameSort.price,
        now: now,
        discountBand: 50,
        platform: GamePlatform.switch2,
      );
      expect(filtered.map((g) => g.id), ['2', '1']);
      expect(
        filterAndSortGames(
          games,
          genre: '전체',
          query: '',
          sort: GameSort.price,
          now: now,
        ),
        hasLength(8),
      );
    },
  );
  test(
    'discount boundaries use displayed percent and never treat full-price games as 0% sales',
    () {
      final now = DateTime.utc(2026, 10, 8);
      final games = [
        exampleGame(id: '49', regular: 20000, discount: 10200),
        exampleGame(
          id: '50',
          regular: 20000,
          discount: 10080,
        ), // 49.6%, displayed 50%.
        exampleGame(id: '59', regular: 20000, discount: 8200),
        exampleGame(
          id: '60',
          regular: 20000,
          discount: 8080,
        ), // 59.6%, displayed 60%.
        exampleGame(id: '0', regular: 20000, discount: 19960),
        exampleGame(id: 'regular', regular: 20000, discount: null),
        exampleGame(id: 'expired', regular: 20000, discount: 10000, end: now),
        exampleGame(id: 'free', regular: 20000, discount: 0),
      ];
      List<String> band(int value) => filterAndSortGames(
        games,
        genre: '전체',
        query: '',
        sort: GameSort.price,
        now: now,
        discountBand: value,
      ).map((g) => g.id).toList();
      expect(band(50), ['59', '50']);
      expect(band(60), ['60']);
      expect(band(0), ['0']);
      expect(band(100), ['free']);
    },
  );
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
