import 'package:flutter/material.dart';
import '../../domain/models/game_item.dart';

class GameFilters extends StatelessWidget {
  const GameFilters({
    super.key,
    required this.discountBand,
    required this.platform,
    required this.onDiscountChanged,
    required this.onPlatformChanged,
    required this.onReset,
  });
  final int? discountBand;
  final GamePlatform? platform;
  final ValueChanged<int?> onDiscountChanged;
  final ValueChanged<GamePlatform?> onPlatformChanged;
  final VoidCallback onReset;

  Future<void> _selectDiscount(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showDialog<int>(
      context: context,
      useSafeArea: true,
      builder: (_) => _FilterOptions(
        title: '할인율 선택',
        description: '표시 할인율 기준 · 50%대는 50~59% 게임이에요.',
        selected: discountBand ?? -1,
        options: [
          (-1, '전체'),
          for (var rate = 0; rate < 100; rate += 10) (rate, '$rate%대'),
          (100, '100%'),
        ],
      ),
    );
    if (context.mounted && result != null) {
      onDiscountChanged(result < 0 ? null : result);
    }
  }

  Future<void> _selectPlatform(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showDialog<int>(
      context: context,
      useSafeArea: true,
      builder: (_) => _FilterOptions(
        title: '기종 선택',
        description: '게임의 출시 기종 기준 · Switch 2 Edition은 Switch 2에 포함돼요.',
        selected: platform == GamePlatform.switch1
            ? 1
            : platform == GamePlatform.switch2
            ? 2
            : -1,
        options: const [(-1, '전체'), (1, 'Switch 1'), (2, 'Switch 2')],
      ),
    );
    if (context.mounted && result != null) {
      onPlatformChanged(
        result == 1
            ? GamePlatform.switch1
            : result == 2
            ? GamePlatform.switch2
            : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilterChip(
        key: const ValueKey('discount-filter-button'),
        selected: discountBand != null,
        showCheckmark: false,
        avatar: const Icon(Icons.percent_rounded, size: 18),
        label: Text(
          discountBand == null
              ? '할인율 전체 ▾'
              : discountBand == 100
              ? '할인율 100% ▾'
              : '할인율 $discountBand%대 ▾',
        ),
        onSelected: (_) => _selectDiscount(context),
      ),
      FilterChip(
        key: const ValueKey('platform-filter-button'),
        selected: platform != null,
        showCheckmark: false,
        avatar: const Icon(Icons.sports_esports_rounded, size: 18),
        label: Text(
          platform == null
              ? '기종 전체 ▾'
              : platform == GamePlatform.switch1
              ? 'Switch 1 ▾'
              : 'Switch 2 ▾',
        ),
        onSelected: (_) => _selectPlatform(context),
      ),
      if (discountBand != null || platform != null)
        IconButton(
          tooltip: '할인율·기종 필터 초기화',
          onPressed: onReset,
          icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
        ),
    ],
  );
}

class _FilterOptions extends StatelessWidget {
  const _FilterOptions({
    required this.title,
    required this.description,
    required this.selected,
    required this.options,
  });
  final String title, description;
  final int selected;
  final List<(int, String)> options;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('filter-options-dialog'),
    insetPadding: const EdgeInsets.all(24),
    scrollable: true,
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: const TextStyle(fontSize: 13, color: Color(0xff747680)),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: options
              .map(
                (option) => ChoiceChip(
                  key: ValueKey('filter-choice-${option.$1}'),
                  label: Text(option.$2),
                  selected: selected == option.$1,
                  onSelected: (_) => Navigator.of(context).pop(option.$1),
                ),
              )
              .toList(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('닫기'),
      ),
    ],
  );
}
