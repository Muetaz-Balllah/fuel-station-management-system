import 'package:flutter/material.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/ui/duty_close_review.dart';

Future<void> showDutyAuditDialog(BuildContext context, DutyRecord duty) {
  return showAppDialog<void>(
    context: context,
    title: 'مراجعة محضر الوردية',
    subtitle: '${duty.fullName} • ${duty.statusLabel}',
    icon: Icons.fact_check_outlined,
    width: 720,
    content: DutyCloseReviewBody(duty: duty),
    actionsBuilder: (dialogContext) => [
      FilledButton(
        onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
        child: const Text('إغلاق'),
      ),
    ],
  );
}

Future<void> showDutyActionErrorDialog(BuildContext context, String message) {
  return showAppDialog<void>(
    context: context,
    title: 'تعذّر تنفيذ الإجراء',
    icon: Icons.error_outline,
    content: Text(message),
    actionsBuilder: (dialogContext) => [
      FilledButton(
        onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
        child: const Text('حسناً'),
      ),
    ],
  );
}
