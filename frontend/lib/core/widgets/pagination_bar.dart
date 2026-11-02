import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';

class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) {
      return const SizedBox.shrink();
    }
    final safeCount = pageCount < 1 ? 1 : pageCount;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Text('الإجمالي: $total', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
          const Spacer(),
          IconButton(
            tooltip: 'السابق',
            onPressed: page <= 1 ? null : () => onPage(page - 1),
            icon: const Icon(Icons.chevron_right),
          ),
          Text('صفحة $page من $safeCount', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'التالي',
            onPressed: page >= safeCount ? null : () => onPage(page + 1),
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }
}
