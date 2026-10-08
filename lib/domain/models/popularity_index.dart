import 'game_item.dart';

/// Positions in Nintendo's US Best Sellers list, not Korean sales figures.
class PopularityIndex {
  const PopularityIndex(this.byId, {this.byTitle = const {}});
  final Map<String, int> byId;
  final Map<String, int> byTitle;

  static String key(String title, String hardware) =>
      '${normalize(hardware)}:${normalize(title)}';

  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');

  // Exact regional titles verified in the KR catalog and US product list.
  // These are title translations, never hard-coded popularity scores.
  static const _officialAliases = {
    '포켓몬스터 파이어레드': '(English) Pokémon FireRed Version',
    '포켓몬스터 리프그린': '(English) Pokémon LeafGreen Version',
    'Pokémon LEGENDS 아르세우스': 'Pokémon Legends: Arceus',
    '마리오 카트 월드': 'Mario Kart World',
    '마리오 카트 8 디럭스': 'Mario Kart 8 Deluxe',
    '모여봐요 동물의 숲': 'Animal Crossing: New Horizons',
    '모여봐요 동물의 숲 Nintendo Switch 2 Edition':
        'Animal Crossing: New Horizons Nintendo Switch 2 Edition',
    '스플래툰 3': 'Splatoon 3',
    '슈퍼 마리오 오디세이': 'Super Mario Odyssey',
    '젤다의 전설 브레스 오브 더 와일드': 'The Legend of Zelda: Breath of the Wild',
    '젤다의 전설 브레스 오브 더 와일드 Nintendo Switch 2 Edition':
        'The Legend of Zelda: Breath of the Wild Nintendo Switch 2 Edition',
    '젤다의 전설 티어스 오브 더 킹덤': 'The Legend of Zelda: Tears of the Kingdom',
    '젤다의 전설 티어스 오브 더 킹덤 Nintendo Switch 2 Edition':
        'The Legend of Zelda: Tears of the Kingdom Nintendo Switch 2 Edition',
    '젤다의 전설 지혜의 투영': 'The Legend of Zelda: Echoes of Wisdom',
    '젤다의 전설 스카이워드 소드 HD': 'The Legend of Zelda: Skyward Sword HD',
    '젤다의 전설 꿈꾸는 섬': "The Legend of Zelda: Link's Awakening",
  };

  int? rankFor(GameItem game) {
    final exactId = byId[game.id];
    if (exactId != null) return exactId;
    for (final title in {game.name, game.originalName}) {
      final candidates = {
        title,
        ...title.split('/'),
        ...RegExp(r'\(([^()]+)\)').allMatches(title).map((m) => m[1]!),
        if (_officialAliases.containsKey(title)) _officialAliases[title]!,
      };
      for (final candidate in candidates) {
        final rank = byTitle[key(candidate, game.hardware)];
        if (rank != null) return rank;
      }
    }
    return null;
  }
}
