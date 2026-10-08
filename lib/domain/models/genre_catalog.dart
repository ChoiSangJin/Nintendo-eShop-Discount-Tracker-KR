/// Conservative fallback categories for established game series when the
/// official Korean catalog omits genres. Unknown titles stay unclassified.
/// These rules classify games; they never translate or rename a title.
List<String> knownGenres(String title) {
  final name = title.toLowerCase();
  const rules = <List<String>, List<String>>{
    ['젤다의 전설', 'legend of zelda']: ['액션', '어드벤처'],
    ['몬스터 헌터', 'monster hunter']: ['액션', 'RPG'],
    [
      '포켓몬',
      'pokémon',
      'pokemon',
      '페르소나',
      'persona',
      '드래곤 퀘스트',
      'dragon quest',
      '파이널 판타지',
      'final fantasy',
      '제노블레이드',
      'xenoblade',
      '로맨싱 사가',
      'romancing saga',
      '옥토패스',
      'octopath',
      '브레이블리',
      'bravely',
      '디스가이아',
      'disgaea',
    ]: [
      'RPG',
    ],
    ['마리오 카트', 'mario kart']: ['레이싱'],
    ['마리오 파티', 'mario party']: ['파티'],
    [
      '마리오 테니스',
      'mario tennis',
      '마리오 골프',
      'mario golf',
      'switch sports',
      'eafc',
      'ea sports',
      'nba 2k',
      '피파',
      'fifa',
    ]: [
      '스포츠',
    ],
    [
      '슈퍼 마리오',
      'super mario',
      '별의 커비',
      'kirby',
      '동키콩',
      'donkey kong',
      '메트로이드',
      'metroid',
      '할로우 나이트',
      'hollow knight',
      'celeste',
      '컵헤드',
      'cuphead',
      '스플래툰',
      'splatoon',
      '베요네타',
      'bayonetta',
      '하데스',
      'hades',
      '젤다무쌍',
      'hyrule warriors',
      '대난투',
      'smash bros',
    ]: [
      '액션',
    ],
    [
      '동물의 숲',
      'animal crossing',
      '스타듀 밸리',
      'stardew valley',
      '마인크래프트',
      'minecraft',
      '목장이야기',
      'story of seasons',
      '룬 팩토리',
      'rune factory',
      'two point',
    ]: [
      '시뮬레이션',
    ],
    [
      '테트리스',
      'tetris',
      '뿌요뿌요',
      'puyo',
      '피크로스',
      'picross',
      'portal',
      '포탈',
      '레벨스',
      'levels',
    ]: [
      '퍼즐',
    ],
    ['레이튼', 'layton', '역전재판', 'ace attorney', 'life is strange']: ['어드벤처'],
  };
  for (final entry in rules.entries) {
    if (entry.key.any(name.contains)) return entry.value;
  }
  return const [];
}
