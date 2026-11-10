import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/core/widgets/dispose_controllers.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/ui/duty_audit_dialog.dart';
import 'package:frontend/features/shifts/ui/duty_close_review.dart';
import 'package:frontend/features/shifts/ui/meter_edit_dialog.dart';

typedef DutyAction = Future<String?> Function(String dutyId);
typedef DutyRejectAction =
    Future<String?> Function(String dutyId, String reason);
typedef DutyMeterAction =
    Future<String?> Function(String dutyId, String reason, List<Map<String, String>> lines);

class DutyApprovalPanel extends StatelessWidget {
  const DutyApprovalPanel({
    super.key,
    required this.duties,
    required this.onApprove,
    required this.onReject,
    this.onAdjustMeters,
    this.title = 'اعتماد إغلاق الورديات',
  });

  final List<DutyRecord> duties;
  final DutyAction onApprove;
  final DutyRejectAction onReject;
  final DutyMeterAction? onAdjustMeters;
  final String title;

  @override
  Widget build(BuildContext context) {
    final pending = duties
        .where((item) => item.status == 'pending_approval')
        .toList();
    final others = duties
        .where((item) => item.status != 'pending_approval')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'تُعرض هنا قراءات العدادات والمبيعات كما أرسلها المشغّل — راجعها ثم اعتمد أو ارفض دون إدخال يدوي.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (duties.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: const Text(
              'لا توجد سجلات إغلاق أو اعتمادات لهذا اليوم. انتقل لتاريخ آخر أو انتظر إرسال المشغّلين لمحاضرهم.',
              style: TextStyle(color: AppColors.onSurfaceVariant, height: 1.5),
            ),
          ),
        if (pending.isNotEmpty) ...[
          const Text(
            'بانتظار اعتماد المشرف',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 8),
          for (final duty in pending)
            DutyApprovalCard(
              duty: duty,
              onApprove: onApprove,
              onReject: onReject,
              onAdjustMeters: onAdjustMeters,
            ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'ورديات أخرى في هذه الجلسة',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final duty in others)
            DutyApprovalCard(
              duty: duty,
              onApprove: onApprove,
              onReject: onReject,
              onAdjustMeters: onAdjustMeters,
              compact: true,
            ),
        ],
      ],
    );
  }
}

class DutyApprovalCard extends StatelessWidget {
  const DutyApprovalCard({
    super.key,
    required this.duty,
    required this.onApprove,
    required this.onReject,
    this.onAdjustMeters,
    this.compact = false,
  });

  final DutyRecord duty;
  final DutyAction onApprove;
  final DutyRejectAction onReject;
  final DutyMeterAction? onAdjustMeters;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pending = duty.status == 'pending_approval';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDutyAuditDialog(context, duty),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: pending
                  ? const Color(0xFFFDBA74)
                  : AppColors.outlineVariant,
              width: pending ? 2 : 1,
            ),
            boxShadow: pending
                ? const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${duty.fullName} • ${duty.employeeCode}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pending
                          ? const Color(0xFFFFFBEB)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      duty.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: pending
                            ? AppColors.warning
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (!compact || pending) ...[
                const SizedBox(height: 12),
                DutyCloseReviewBody(duty: duty),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${duty.liters ?? '—'} لتر • ${duty.varianceLabel ?? '—'}',
                  ),
                ),
              if (duty.meterAdjusted && compact)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'تم تعديل عداد المسدس — افتح المحضر لرؤية القراءة السابقة والسبب',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                  ),
                ),
              if (pending) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: Key('duty-approve-${duty.id}'),
                      onPressed: () => _approve(context),
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('اعتماد المحضر'),
                    ),
                    if (onAdjustMeters != null)
                      OutlinedButton.icon(
                        onPressed: () => _adjust(context),
                        icon: const Icon(Icons.speed, size: 18),
                        label: const Text('تعديل العداد'),
                      ),
                    OutlinedButton.icon(
                      key: Key('duty-reject-${duty.id}'),
                      onPressed: () => _reject(context),
                      icon: const Icon(Icons.highlight_off_outlined, size: 18),
                      label: const Text('رفض وإرجاع للمشغّل'),
                    ),
                  ],
                ),
              ],
              if (!pending)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'اضغط على البطاقة لعرض المحضر الكامل',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.9),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    final message = await onApprove(duty.id);
    if (message != null && context.mounted) {
      await showDutyActionErrorDialog(context, message);
    }
  }

  Future<void> _adjust(BuildContext context) async {
    final request = await showMeterEditDialog(context, lines: duty.lines, adjustments: duty.meterAdjustments);
    if (request == null || !context.mounted || onAdjustMeters == null) {
      return;
    }
    final message = await onAdjustMeters!(duty.id, request.reason, request.lines);
    if (message != null && context.mounted) {
      await showDutyActionErrorDialog(context, message);
    }
  }

  Future<void> _reject(BuildContext context) async {
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return DisposeControllers(
          controllers: [reason],
          child: AlertDialog(
            title: const Text('رفض الوردية'),
            content: TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'سبب الرفض'),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  final message = await onReject(duty.id, reason.text);
                  if (!dialogContext.mounted) {
                    return;
                  }
                  Navigator.pop(dialogContext);
                  if (message != null && context.mounted) {
                    await showDutyActionErrorDialog(context, message);
                  }
                },
                child: const Text('رفض'),
              ),
            ],
          ),
        );
      },
    );
  }
}
