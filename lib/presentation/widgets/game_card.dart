import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models/game_item.dart';

String won(int? amount) =>
    amount == null ? '가격 확인 불가' : '₩${NumberFormat('#,##0').format(amount)}';
String koreanDate(DateTime date) => DateFormat(
  'yyyy.MM.dd HH:mm',
).format(date.toUtc().add(const Duration(hours: 9)));

class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.favorite,
    required this.onFavorite,
    required this.now,
  });
  final GameItem game;
  final bool favorite;
  final VoidCallback onFavorite;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final rate = game.discountRateAt(now);
    final sale = game.saleActiveAt(now);
    return Semantics(
      container: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showGameDetails(context, game, now),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: GameBanner(game: game),
                  ),
                  if (sale)
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffe60012),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '-$rate%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xd9ffffff),
                      ),
                      child: IconButton(
                        tooltip: favorite ? '관심 게임에서 삭제' : '관심 게임에 추가',
                        onPressed: onFavorite,
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                        color: favorite
                            ? const Color(0xffe60012)
                            : const Color(0xff343640),
                        isSelected: favorite,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      game.genres.isEmpty
                          ? game.hardware
                          : '${game.hardware} · ${game.genres.take(3).join(' · ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          won(game.priceAt(now)),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: Color(0xff171a22),
                          ),
                        ),
                        if (sale)
                          Text(
                            won(game.regularPrice),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                    if (sale && game.discountEnd != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _deadline(game.discountEnd!),
                        style: const TextStyle(
                          color: Color(0xffbf381b),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (game.priceCheckedAt != null &&
                        now.difference(game.priceCheckedAt!) >
                            const Duration(minutes: 15)) ...[
                      const SizedBox(height: 6),
                      Text(
                        '마지막 조회 가격 · ${koreanDate(game.priceCheckedAt!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _deadline(DateTime end) {
    final hours = end.difference(now).inHours;
    return hours < 24
        ? '할인 마감까지 ${hours < 1 ? '1시간 미만' : '$hours시간'}'
        : '${end.difference(now).inDays}일 후 할인 마감';
  }
}

class GameBanner extends StatelessWidget {
  const GameBanner({super.key, required this.game});
  final GameItem game;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xffeae8e2),
      child: const Center(
        child: Icon(
          Icons.sports_esports_rounded,
          size: 44,
          color: Color(0xffb1afa7),
        ),
      ),
    );
    if (game.bannerUrl == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: game.bannerUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 900,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

Future<void> showGameDetails(
  BuildContext context,
  GameItem game,
  DateTime now,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .75,
    minChildSize: .4,
    maxChildSize: .95,
    builder: (_, scrollController) => SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: GameBanner(game: game),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            game.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (game.originalName != game.name) ...[
            const SizedBox(height: 6),
            Text(
              game.originalName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            won(game.priceAt(now)),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          if (game.saleActiveAt(now))
            Text(
              '정가 ${won(game.regularPrice)} · ${game.discountRateAt(now)}% 할인',
            ),
          const SizedBox(height: 16),
          Text('플랫폼  ${game.hardware}'),
          if (game.genres.isNotEmpty) Text('장르  ${game.genres.join(' · ')}'),
          if (game.releaseDate != null)
            Text('출시일  ${DateFormat('yyyy.MM.dd').format(game.releaseDate!)}'),
          if (game.saleActiveAt(now) && game.discountEnd != null)
            Text('할인 마감  ${koreanDate(game.discountEnd!)} (한국 시간)'),
          if (game.priceCheckedAt != null)
            Text('가격 조회  ${koreanDate(game.priceCheckedAt!)} (한국 시간)'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('한국 공식 스토어에서 보기'),
              onPressed: () async {
                var opened = false;
                try {
                  opened = await launchUrl(
                    Uri.parse('https://store.nintendo.co.kr/${game.id}'),
                    mode: LaunchMode.externalApplication,
                  );
                } on Object {
                  /* Surface a launch failure below. */
                }
                if (!opened && sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('브라우저를 열지 못했습니다.')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '가격과 할인 기간은 변경될 수 있습니다. 구매 전 공식 스토어에서 최종 가격을 확인해 주세요.',
            style: TextStyle(fontSize: 12, color: Color(0xff666872)),
          ),
        ],
      ),
    ),
  ),
);
