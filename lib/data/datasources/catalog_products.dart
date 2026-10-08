import '../../domain/models/game_item.dart';

/// Product links verified on Nintendo's Korean pages on 2026-10-08.
/// Key by Contentful record ID, never by placeholder NSUID (e.g. 0001 is
/// shared by Scarlet/Violet and Labo). Only include the corresponding software,
/// not recommendations, DLC or Switch 2 upgrade passes found on the same page.
const verifiedCatalogProducts = <String, List<(String, String)>>{
  // https://www.nintendo.com/kr/switch/sv/
  '3eHGcNQqWT0hFf8U9Blxrz': [
    ('70010000053968', '포켓몬스터 스칼렛'),
    ('70010000053973', '포켓몬스터 바이올렛'),
  ],
  // https://www.nintendo.com/kr/switch/pokemonbdsp/index.html
  'mpkilVs8BNauL1vVMnooy': [
    ('70010000039952', '포켓몬스터 브릴리언트 다이아몬드'),
    ('70010000039957', '포켓몬스터 샤이닝 펄'),
  ],
  // https://www.nintendo.com/kr/switch/sword_shield/
  '5fQdHlcRCjcj1dqn118zxs': [
    ('70010000026251', '포켓몬스터 소드'),
    ('70010000026252', '포켓몬스터 실드'),
  ],
  // https://www.nintendo.com/kr/switch/pikachu_eevee/
  'dzAe3N5a3Rb1LC7hzHzmJ': [
    ('70010000015694', '포켓몬스터 레츠고! 피카츄'),
    ('70010000015693', '포켓몬스터 레츠고! 이브이'),
  ],
  // https://www.nintendo.com/kr/switch/bpdpa/
  '3TWYcSrux8ElXCp3sdWfEn': [
    ('70070000030781', '슈퍼 마리오 갤럭시 + 슈퍼 마리오 갤럭시 2'),
    ('70010000104189', '슈퍼 마리오 갤럭시'),
    ('70010000104194', '슈퍼 마리오 갤럭시 2'),
  ],
  // https://www.nintendo.com/kr/switch/bgw5a/
  '1LXkEdHNOWt5iriK9bzi9K': [('70010000095684', '메트로이드 프라임 4 비욘드')],
  // https://www.nintendo.com/kr/switch/fitboxing3/
  '2ONajAKkmFCToDdiYFuVHI': [
    ('70010000089523', 'Fitness Boxing 3: Your Personal Trainer'),
  ],
  // https://www.nintendo.com/kr/switch/bflta/
  '4bl9wvif2YtLTSpiexBwfg': [('70010000122820', '리듬 천국 미라클 스타즈')],
};

Iterable<Map<String, dynamic>> expandCatalogRecord(
  Map<String, dynamic> record,
) sync* {
  final recordId = record['sys']['id'] as String;
  final products = verifiedCatalogProducts[recordId];
  if (products != null) {
    for (final (id, title) in products) {
      yield {...record, 'nsuid': id, 'title': title};
    }
    return;
  }
  var id = record['nsuid']?.toString() ?? '';
  if (!isStoreId(id)) {
    // Some catalog records have a placeholder but a valid direct KR store link.
    final source = catalogSourceUrl(record['pageLinkCustom']);
    final uri = source == null ? null : Uri.tryParse(source);
    if (uri?.host == 'store.nintendo.co.kr' &&
        uri!.pathSegments.length == 1 &&
        isStoreId(uri.pathSegments.single)) {
      id = uri.pathSegments.single;
    } else {
      // Preserve searchable official metadata, without inventing a store ID.
      id = 'catalog:$recordId';
    }
  }
  yield {...record, 'nsuid': id};
}
