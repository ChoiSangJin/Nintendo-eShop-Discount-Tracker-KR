import 'game_item.dart';

/// Official Korean paid-download rankings, kept separate for each platform.
class PopularityIndex {
  const PopularityIndex(
    this.byId, {
    required this.source,
    this.entries = const [],
  });
  final Map<String, int> byId;
  final String source;
  final List<PopularityEntry> entries;

  static String? periodLabel(String? source) {
    final match = RegExp(r'^kr:(\d{4}):(1st|full)$').firstMatch(source ?? '');
    if (match == null) return null;
    return '${match[1]}년 ${match[2] == '1st' ? '상반기' : '연간'}';
  }

  int? rankFor(GameItem game) {
    final rank = byId[game.id];
    if (rank == null) return null;
    if (entries.isEmpty) return rank;
    for (final entry in entries) {
      if (entry.id == game.id && entry.platform == game.platform) return rank;
    }
    return null;
  }
}

class PopularityEntry {
  const PopularityEntry(this.id, this.title, this.platform, this.rank);
  final String id;
  final String title;
  final GamePlatform platform;
  final int rank;
}
