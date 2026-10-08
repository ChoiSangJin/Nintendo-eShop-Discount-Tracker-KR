import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/domain/models/popularity_index.dart';

GameItem title(String name, {String hardware = 'Nintendo Switch'}) => GameItem(
  id: '70010000000001',
  name: name,
  originalName: name,
  hardware: hardware,
);

void main() {
  test(
    'regional IDs match exact English title and hardware, keeping editions distinct',
    () {
      final index = PopularityIndex(
        {'70010000000999': 1},
        byTitle: {
          PopularityIndex.key('Hogwarts Legacy', 'Nintendo Switch'): 1,
          PopularityIndex.key('Hogwarts Legacy', 'Nintendo Switch 2'): 19,
        },
      );
      expect(index.rankFor(title('호그와트 레거시 (Hogwarts Legacy)')), 1);
      expect(
        index.rankFor(
          title('호그와트 레거시 (Hogwarts Legacy)', hardware: 'Nintendo Switch 2'),
        ),
        19,
      );
      expect(
        index.rankFor(title('Hogwarts Legacy Digital Deluxe Edition')),
        isNull,
      );
      expect(index.rankFor(title('Hogwarts')), isNull);
    },
  );
  test(
    'verified Korean Pokémon alias uses current list position without a fixed score',
    () {
      final key = PopularityIndex.key(
        'Pokémon™ Legends: Arceus',
        'Nintendo Switch',
      );
      expect(
        PopularityIndex(
          {},
          byTitle: {key: 81},
        ).rankFor(title('Pokémon LEGENDS 아르세우스')),
        81,
      );
      expect(
        PopularityIndex(
          {},
          byTitle: {key: 7},
        ).rankFor(title('Pokémon LEGENDS 아르세우스')),
        7,
      );
      expect(
        PopularityIndex({}).rankFor(title('Pokémon LEGENDS 아르세우스')),
        isNull,
      );
    },
  );
}
