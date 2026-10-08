import 'package:flutter/material.dart';
import '../../domain/models/game_item.dart';

class GamePlatformBadge extends StatelessWidget {
  const GamePlatformBadge({super.key, required this.game});
  final GameItem game;

  @override
  Widget build(BuildContext context) {
    final switch2 = game.platform == GamePlatform.switch2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: switch2 ? const Color(0xffe60012) : const Color(0xffeeeff3),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sports_esports_rounded,
            size: 15,
            color: switch2 ? Colors.white : const Color(0xff464752),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              game.platformLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: switch2 ? Colors.white : const Color(0xff464752),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
