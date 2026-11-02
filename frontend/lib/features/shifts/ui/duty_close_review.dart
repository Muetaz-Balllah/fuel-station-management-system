import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';
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
        if (duty.lines.isEmpty)
          const Text('لا توجد قراءات مسجّلة.')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final table = _LinesTable(lines: duty.lines);
              if (constraints.maxWidth >= 720) {
                return table;
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 720, child: table),
              );
            },
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

  final List<DutyLine> lines;

  @override
  Widget build(BuildContext context) {
    const header = TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
    const cell = TextStyle(fontSize: 12);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.1),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(0.9),
        5: FlexColumnWidth(0.8),
        6: FlexColumnWidth(0.9),
      },
      border: TableBorder.all(color: const Color(0xFFE2E8F0)),
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
          children: [
            Padding(padding: EdgeInsets.all(8), child: Text('المضخة', style: header)),
            Padding(padding: EdgeInsets.all(8), child: Text('المسدس / المنتج', style: header)),
            Padding(padding: EdgeInsets.all(8), child: Text('افتتاحي', style: header)),
            Padding(padding: EdgeInsets.all(8), child: Text('ختامي', style: header)),
            Padding(padding: EdgeInsets.all(8), child: Text('المباع', style: header)),
            Padding(padding: EdgeInsets.all(8), child: Text('السعر', style: header)),
            Padding(padding: EdgeInsets.all(8), child: Text('الإيراد', style: header)),
          ],
        ),
        for (final line in lines)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(line.pumpCode, style: cell)),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${line.nozzleCode} • ${line.productName}\n${line.label}', style: cell),
              ),
              Padding(padding: const EdgeInsets.all(8), child: Text(line.openingMeter, style: cell)),
              Padding(padding: const EdgeInsets.all(8), child: Text(line.closingMeter ?? '—', style: cell)),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(line.liters ?? _sold(line.openingMeter, line.closingMeter), style: cell),
              ),
              Padding(padding: const EdgeInsets.all(8), child: Text('${line.unitPrice} د.ل', style: cell)),
              Padding(padding: const EdgeInsets.all(8), child: Text(line.lineAmount ?? '—', style: cell)),
            ],
          ),
      ],
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
