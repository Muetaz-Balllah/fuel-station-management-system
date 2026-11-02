import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData icon = Icons.info_outline,
  required Widget content,
  List<Widget>? actions,
  double width = 440,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.outlineVariant),
              boxShadow: const [
                BoxShadow(color: Color(0x26041539), blurRadius: 32, offset: Offset(0, 16)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7EEFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(subtitle, style: const TextStyle(color: AppColors.onSurfaceVariant, height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: AppColors.outline),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: content,
                ),
                if (actions != null && actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var index = 0; index < actions.length; index++) ...[
                          if (index > 0) const SizedBox(width: 8),
                          actions[index],
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
