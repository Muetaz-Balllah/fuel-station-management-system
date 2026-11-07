import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/core/widgets/horizontal_data_table.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/logic/duty_format.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';

class DutyCloseReviewBody extends StatelessWidget {
  const DutyCloseReviewBody({super.key, required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    final pending = duty.status == 'pending_approval';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetaStrip(duty: duty),
        const SizedBox(height: 12),
        Text(
          pending ? 'محضر الإغلاق المرسل من المشغّل (للمراجعة والاعتماد)' : 'تفاصيل الوردية',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        if (duty.meterAdjusted) ...[
          _MeterAdjustmentNotice(duty: duty),
          const SizedBox(height: 8),
        ],
        if (duty.lines.isEmpty)
          const Text('لا توجد قراءات مسجّلة.')
        else
          HorizontalDataTable(
            minWidth: _LinesTable.minWidth,
            child: _LinesTable(lines: duty.lines),
          ),
        const SizedBox(height: 12),
        _TotalsStrip(duty: duty),
      ],
    );
  }
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if ((duty.templateName ?? '').isNotEmpty) _chip('الوردية', duty.templateName!),
      if ((duty.businessDate).isNotEmpty) _chip('التاريخ', duty.businessDate),
      _chip('ساعات الدوام', dutyWorkHoursLabel(duty)),
      if ((duty.openedAtLabel ?? '').isNotEmpty) _chip('بدء العهدة', duty.openedAtLabel!),
      if ((duty.closedAtLabel ?? '').isNotEmpty) _chip('إغلاق العهدة', duty.closedAtLabel!),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }
}

class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.lines});

  /// Column widths plus horizontal row padding (8 + 8).
  static const minWidth = 720.0;
  static const pump = 72.0;
  static const nozzle = 168.0;
  static const opening = 108.0;
  static const closing = 108.0;
  static const sold = 88.0;
  static const price = 72.0;
  static const amount = 88.0;

  final List<DutyLine> lines;

  @override
  Widget build(BuildContext context) {
    const header = TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
    const cell = TextStyle(fontSize: 12);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: const Row(
              children: [
                SizedBox(width: pump, child: Text('المضخة', style: header)),
                SizedBox(width: nozzle, child: Text('المسدس / المنتج', style: header)),
                SizedBox(width: opening, child: Text('افتتاحي', style: header)),
                SizedBox(width: closing, child: Text('ختامي', style: header)),
                SizedBox(width: sold, child: Text('المباع', style: header)),
                SizedBox(width: price, child: Text('السعر', style: header)),
                SizedBox(width: amount, child: Text('الإيراد', style: header)),
              ],
            ),
          ),
          for (final line in lines)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: pump,
                    child: Text(line.pumpCode, style: cell, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(
                    width: nozzle,
                    child: Text(
                      '${line.nozzleCode} • ${line.productName}\n${line.label}',
                      style: cell,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                  SizedBox(
                    width: opening,
                    child: Text(
                      line.meterAdjusted ? '${line.openingMeter}\nعُدّل من ${line.previousMeter ?? '—'}' : line.openingMeter,
                      style: cell.copyWith(color: line.meterAdjusted ? const Color(0xFFB45309) : null, fontWeight: line.meterAdjusted ? FontWeight.w700 : null),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: closing,
                    child: Text(line.closingMeter ?? '—', style: cell, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(
                    width: sold,
                    child: Text(
                      line.liters ?? _sold(line.openingMeter, line.closingMeter),
                      style: cell,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: price,
                    child: Text('${line.unitPrice} د.ل', style: cell, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(
                    width: amount,
                    child: Text(line.lineAmount ?? '—', style: cell, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _sold(String opening, String? closing) {
    if (closing == null || closing.isEmpty) {
      return '—';
    }
    final preview = previewDuty(
      lines: [PreviewLine(opening: opening, closing: closing, unitPrice: '1')],
      cash: '0',
    );
    return preview?.liters ?? '—';
  }
}

class _MeterAdjustmentNotice extends StatelessWidget {
  const _MeterAdjustmentNotice({required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    final notes = duty.meterAdjustments.isNotEmpty
        ? duty.meterAdjustments
        : [
            for (final line in duty.lines.where((item) => item.meterAdjusted))
              MeterAdjustment(
                nozzleCode: line.nozzleCode,
                previousMeter: line.previousMeter ?? '—',
                newMeter: line.openingMeter,
                reason: line.meterReason ?? '',
                actorName: line.adjustedByName ?? '',
                createdAtLabel: '',
              ),
          ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تعديل على عداد المسدس',
            style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
          ),
          const SizedBox(height: 6),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'مسدس ${note.nozzleCode}: من ${note.previousMeter} إلى ${note.newMeter}'
                '${note.actorName.isEmpty ? '' : ' • ${note.actorName}'}'
                '${note.reason.isEmpty ? '' : ' • السبب: ${note.reason}'}',
                style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF92400E)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _total('إجمالي اللترات', '${duty.liters ?? '—'} لتر'),
          _total('الإيراد المحتسب', '${duty.expectedCash ?? '—'} د.ل'),
          _total('النقدية المسلّمة', '${duty.cashHanded ?? '—'} د.ل'),
          _total('المطابقة', duty.varianceLabel ?? '—'),
        ],
      ),
    );
  }

  Widget _total(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      ],
    );
  }
}
