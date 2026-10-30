import 'package:flutter_test/flutter_test.dart';
import 'package:switch_sale_tracker/domain/models/game_item.dart';
import 'package:switch_sale_tracker/domain/models/popularity_index.dart';
import 'support/fakes.dart';

void main() {
  test(
    'Korean rankings match exact IDs and platform, with no regional aliases',
    () {
      final index = PopularityIndex(
        {'70010000000001': 5},
        source: 'kr:2027:full',
        entries: [
          const PopularityEntry(
            '70010000000001',
            '공식 제목',
            GamePlatform.switch1,
            5,
          ),
        ],
      );
      expect(index.rankFor(exampleGame()), 5);
      expect(
        index.rankFor(exampleGame(id: '70010000000002', name: '공식 제목')),
        isNull,
      );
      expect(index.rankFor(exampleGame(hardware: 'Nintendo Switch 2')), isNull);
      expect(PopularityIndex.periodLabel(index.source), '2027년 연간');
      expect(PopularityIndex.periodLabel('us:2027:full'), isNull);
    },
  );
  test(
    'rank source survives names, prices and cache; old US ranks stay unverified',
    () {
      final game = exampleGame().withPopularityRank(8, source: 'kr:2026:1st');
      final restored = GameItem.fromJson(
        game.withName('공식 제목').withPrice({
          'regular_price': {'raw_value': '10000'},
          'discount_price': {'raw_value': '5000'},
        }, DateTime.now()).toJson(),
      );
      expect(restored.hasKoreanPopularity, isTrue);
      expect(restored.popularityRank, 8);
      expect(restored.popularitySource, 'kr:2026:1st');
      expect(exampleGame().withPopularityRank(1).hasKoreanPopularity, isFalse);
    },
  );
}
