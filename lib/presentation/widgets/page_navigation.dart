import 'dart:math' as math;
import 'package:flutter/material.dart';

class PageNavigation extends StatelessWidget {
  const PageNavigation({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.enabled = true,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final bool enabled;
  static const _groupSize = 5;

  @override
  Widget build(BuildContext context) {
    final groupStart = page ~/ _groupSize * _groupSize;
    final groupEnd = math.min(groupStart + _groupSize, pageCount);
    final numberStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Tooltip(
            message: '이전 5페이지',
            child: OutlinedButton.icon(
              onPressed: enabled && groupStart > 0
                  ? () => onPageChanged(groupStart - _groupSize)
                  : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('이전'),
            ),
          ),
          for (var index = groupStart; index < groupEnd; index++)
            Semantics(
              selected: index == page,
              label: '${index + 1}페이지',
              child: index == page
                  ? FilledButton(
                      style: numberStyle,
                      onPressed: enabled ? () => onPageChanged(index) : null,
                      child: Text('${index + 1}'),
                    )
                  : OutlinedButton(
                      style: numberStyle,
                      onPressed: enabled ? () => onPageChanged(index) : null,
                      child: Text('${index + 1}'),
                    ),
            ),
          Tooltip(
            message: '다음 5페이지',
            child: OutlinedButton.icon(
              onPressed: enabled && groupEnd < pageCount
                  ? () => onPageChanged(groupEnd)
                  : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('다음'),
            ),
          ),
        ],
      ),
    );
  }
}
