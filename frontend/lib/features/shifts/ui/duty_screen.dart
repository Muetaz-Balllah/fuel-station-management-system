import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/settings/data/shift_roster.dart';
import 'package:frontend/features/shifts/logic/cubit/duty_cubit.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';

class DutyView extends StatelessWidget {
  const DutyView({super.key, this.onShowHistory, this.photo});

  final VoidCallback? onShowHistory;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DutyCubit>().state;
    final session = context.watch<SessionCubit>().state;
    final user = session is SessionSignedIn ? session.user : null;
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.all(wide ? 32 : 16),
      children: [
        if (wide) ...[
          const _DesktopTitle(),
          const _DesktopMetaRow(),
          _ProfileBanner(user: user, state: state, photo: photo, wide: wide),
        ] else
          _MobileProfileCard(user: user, state: state, photo: photo),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(state.error!, key: const Key('duty-error'), style: const TextStyle(color: AppColors.error)),
          ),
        const SizedBox(height: 16),
        if (state.duty == null && !state.canOpen)
          Text(
            state.reason ?? 'لا توجد وردية مكلّفة لك اليوم.',
            key: const Key('duty-blocked'),
            style: const TextStyle(fontSize: 18, height: 1.6),
          )
        else if (wide)
          _DesktopBody(state: state, onShowHistory: onShowHistory)
        else
          _PhoneBody(state: state, onShowHistory: onShowHistory),
        if (wide) ...[
          const SizedBox(height: 20),
          const ScheduleBoard(),
          const SizedBox(height: 12),
          const _SafetyNote(),
        ],
      ],
    );
  }
}

class _DesktopMetaRow extends StatefulWidget {
  const _DesktopMetaRow();

  @override
  State<_DesktopMetaRow> createState() => _DesktopMetaRowState();
}

class _DesktopMetaRowState extends State<_DesktopMetaRow> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${now.day}/${now.month}/${now.year}';
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today, size: 18, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(date, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              const Icon(Icons.schedule, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(time, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileProfileCard extends StatelessWidget {
  const _MobileProfileCard({required this.user, required this.state, required this.photo});

  final dynamic user;
  final DutyState state;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final name = user == null ? '' : user.fullName as String;
    final code = user == null ? '' : user.employeeCode as String;
    final pumps = state.nozzles.map((item) => '${item.pumpCode} (${item.productName})').toSet().join(' • ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEFF)),
        boxShadow: const [BoxShadow(color: Color(0x0A041539), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: photo == null
                      ? const ColoredBox(color: Color(0xFFE7EEFF), child: Icon(Icons.person, color: AppColors.primary))
                      : Image.memory(photo!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    Text('فني مضخات رئيسي ($code)', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFECFDF3), borderRadius: BorderRadius.circular(99)),
                child: const Text('وردية جارية', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF0F3FF), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('الوردية الحالية', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  Text(state.templateName ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ])),
                if (state.duty?.openedAt != null) _Elapsed(openedAt: state.duty!.openedAt!, large: true),
              ],
            ),
          ),
          if (pumps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFE7EEFF), borderRadius: BorderRadius.circular(10)),
              child: Text('المضخات المكلّف بها: $pumps', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopTitle extends StatelessWidget {
  const _DesktopTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بوابة الموظف  ›  إدارة مناوبة العمل وتسليم العهدة', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
          SizedBox(height: 4),
          Text('واجهة تسجيل وقراءات المناوبة اليومية', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.user, required this.state, required this.photo, required this.wide});

  final dynamic user;
  final DutyState state;
  final Uint8List? photo;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final name = user == null ? '' : user.fullName as String;
    final code = user == null ? '' : user.employeeCode as String;
    final pumps = state.nozzles.map((item) => '${item.pumpCode} (${item.productName})').toSet().join(' • ');
    final profile = Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 64,
            height: 64,
            child: photo == null
                ? const ColoredBox(
                    color: Color(0xFF0F172A),
                    child: Icon(Icons.person, color: Colors.white),
                  )
                : Image.memory(photo!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('فني مضخات ووردية ($code)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              if (pumps.isNotEmpty)
                Text('المضخات المكلفة: $pumps', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              if ((state.templateName ?? '').isNotEmpty)
                Text(state.templateName!, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
    final shiftBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.duty == null ? 'الوردية غير مفتوحة' : 'الوردية نشطة ومفتوحة الآن',
            style: TextStyle(fontWeight: FontWeight.w700, color: state.duty == null ? AppColors.onSurfaceVariant : AppColors.success),
          ),
          if ((state.templateName ?? '').isNotEmpty) Text(state.templateName!, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          if (state.duty?.openedAt != null) _Elapsed(openedAt: state.duty!.openedAt!, large: wide),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: profile),
                const SizedBox(width: 16),
                shiftBox,
              ],
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [profile, const SizedBox(height: 12), shiftBox]),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Text(
        'تنبيه السلامة الميدانية: يرجى التأكد من ارتداء سترة السلامة العاكسة وفحص زر إيقاف الطوارئ (ESD) عند استلام وتسليم الوردية.',
        style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
      ),
    );
  }
}

class _DesktopBody extends StatelessWidget {
  const _DesktopBody({required this.state, required this.onShowHistory});

  final DutyState state;
  final VoidCallback? onShowHistory;

  @override
  Widget build(BuildContext context) {
    final duty = state.duty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (duty == null)
          _OpenCard(state: state)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final opening = _OpeningCard(duty: duty);
              final close = duty.canClose ? _CloseForm(duty: duty, compact: false) : _Waiting(duty: duty);
              if (constraints.maxWidth < 860) {
                return Column(children: [opening, const SizedBox(height: 16), close]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(flex: 4, child: opening),
                  const SizedBox(width: 16),
                  Expanded(flex: 8, child: close),
                ],
              );
            },
          ),
        const SizedBox(height: 24),
        _HistorySection(state: state, onShowHistory: onShowHistory),
      ],
    );
  }
}

class _PhoneBody extends StatefulWidget {
  const _PhoneBody({required this.state, required this.onShowHistory});

  final DutyState state;
  final VoidCallback? onShowHistory;

  @override
  State<_PhoneBody> createState() => _PhoneBodyState();
}

class _PhoneBodyState extends State<_PhoneBody> {
  int _segment = 1;

  @override
  Widget build(BuildContext context) {
    final duty = widget.state.duty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE7EEFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.swap_horiz, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('إدارة دورة الوردية', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFFF0F3FF), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    _MobileTab(label: 'فتح وردية جديدة', selected: _segment == 0, onTap: () => setState(() => _segment = 0)),
                    _MobileTab(label: 'إغلاق الوردية وتسليم العهدة', selected: _segment == 1, onTap: () => setState(() => _segment = 1)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_segment == 0)
                duty == null ? _OpenCard(state: widget.state) : _OpeningCard(duty: duty)
              else if (duty == null)
                const Text('افتح الوردية أولاً ثم أدخل قراءات الإغلاق.')
              else if (duty.canClose)
                _CloseForm(duty: duty, compact: true)
              else
                _Waiting(duty: duty),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _MobileHistoryPreview(state: widget.state, onShowHistory: widget.onShowHistory),
      ],
    );
  }
}

class _MobileTab extends StatelessWidget {
  const _MobileTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileHistoryPreview extends StatelessWidget {
  const _MobileHistoryPreview({required this.state, required this.onShowHistory});

  final DutyState state;
  final VoidCallback? onShowHistory;

  @override
  Widget build(BuildContext context) {
    final rows = state.history.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('آخر الورديات المعتمدة', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))),
            TextButton(onPressed: onShowHistory, child: const Text('عرض السجل الكامل')),
          ],
        ),
        for (final row in rows) _HistoryCard(row: row, mobile: true),
        if (rows.isEmpty) const Text('لا توجد ورديات سابقة.'),
      ],
    );
  }
}

class _OpenCard extends StatelessWidget {
  const _OpenCard({required this.state});

  final DutyState state;

  @override
  Widget build(BuildContext context) {
    final nozzles = state.nozzles.where((item) => item.selectable).toList();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('فتح وردية جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final nozzle in nozzles)
            Text('${nozzle.pumpCode} • مسدس ${nozzle.code} — آخر إغلاق ${nozzle.currentMeter}'),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('duty-open'),
            onPressed: state.busy ? null : () => context.read<DutyCubit>().openAssigned(),
            child: const Text('فتح الوردية'),
          ),
        ],
      ),
    );
  }
}

class _OpeningCard extends StatelessWidget {
  const _OpeningCard({required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FFFB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF86EFAC), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.login, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(child: Text('1. فتح الوردية وقراءة البداية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              _Chip(text: 'معتمد'),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in duty.lines)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                children: [
                  Expanded(child: Text('${line.pumpCode} (${line.productName})')),
                  Text(line.openingMeter, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const Text('تم بدء المناوبة بنجاح والمضخات متصلة بالنظام.', style: TextStyle(color: AppColors.success, fontSize: 12)),
        ],
      ),
    );
  }
}

String? _lineSoldLiters(String opening, String closing) {
  final preview = previewDuty(
    lines: [PreviewLine(opening: opening, closing: closing, unitPrice: '1')],
    cash: '0',
  );
  if (preview == null) {
    return null;
  }
  return '+${groupThousands(preview.liters)} لتر';
}

class _PumpCloseField extends StatelessWidget {
  const _PumpCloseField({required this.line, required this.controller, required this.onChanged});

  final DutyLine line;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final sold = _lineSoldLiters(line.openingMeter, controller.text);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${line.pumpCode} (${line.productName})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                ],
              ),
              Text('افتتاحي: ${line.openingMeter}', style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('close-${line.nozzleId}'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'قراءة العداد الختامية (لتر)'),
            onChanged: (_) => onChanged(),
          ),
          if (sold != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('الكمية المباعة المحتسبة:', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  Text(sold, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.title, required this.value, required this.color, this.emphasize = false});

  final String title;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: emphasize ? 16 : 18, fontWeight: FontWeight.w800, color: emphasize ? AppColors.error : AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _MobileSummary extends StatelessWidget {
  const _MobileSummary({required this.preview, this.unitPrice});

  final DutyPreview? preview;
  final String? unitPrice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('إجمالي اللترات المباعة: ${preview == null ? '—' : groupThousands(preview!.liters)} لتر', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('التسعيرة الرسمية للتر: ${unitPrice == null ? '—' : '$unitPrice د.ل'}'),
          const SizedBox(height: 6),
          Text(
            'المبلغ المستحق للصندوق: ${preview == null ? '—' : '${preview!.expectedCash} د.ل'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          if (preview != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFECFDF3), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${preview!.phrase} (${preview!.variance} د.ل)', key: const Key('duty-variance'), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    final pending = duty.status == 'pending_approval';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(duty.statusLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
          if (duty.varianceLabel != null) Text(duty.varianceLabel!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: null,
            child: Text(pending ? 'تم رفع المحضر وانتظار توقيع المشرف' : duty.statusLabel),
          ),
        ],
      ),
    );
  }
}

class _CloseForm extends StatefulWidget {
  const _CloseForm({required this.duty, this.compact = false});

  final DutyRecord duty;
  final bool compact;

  @override
  State<_CloseForm> createState() => _CloseFormState();
}

class _CloseFormState extends State<_CloseForm> {
  late final Map<String, TextEditingController> _closings;
  late final TextEditingController _cash;

  @override
  void initState() {
    super.initState();
    _closings = {
      for (final line in widget.duty.lines) line.nozzleId: TextEditingController(),
    };
    _cash = TextEditingController();
  }

  @override
  void dispose() {
    for (final controller in _closings.values) {
      controller.dispose();
    }
    _cash.dispose();
    super.dispose();
  }

  DutyPreview? get _preview {
    return previewDuty(
      lines: [
        for (final line in widget.duty.lines)
          PreviewLine(
            opening: line.openingMeter,
            closing: _closings[line.nozzleId]?.text ?? '',
            unitPrice: line.unitPrice,
          ),
      ],
      cash: _cash.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final prices = widget.duty.lines.map((line) => line.unitPrice).toSet();
    final wide = !widget.compact && MediaQuery.sizeOf(context).width >= 860;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFDBA74), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('2. نموذج إنهاء الوردية وتسليم العهدة (المطابقة الفورية)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (prices.length == 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${prices.first} د.ل / لتر', style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in widget.duty.lines) ...[
                  if (line != widget.duty.lines.first) const SizedBox(width: 12),
                  Expanded(child: _PumpCloseField(line: line, controller: _closings[line.nozzleId]!, onChanged: () => setState(() {}))),
                ],
              ],
            )
          else
            for (final line in widget.duty.lines)
              _PumpCloseField(line: line, controller: _closings[line.nozzleId]!, onChanged: () => setState(() {})),
          const SizedBox(height: 12),
          if (widget.compact)
            _MobileSummary(
              preview: preview,
              unitPrice: widget.duty.lines.isEmpty ? null : widget.duty.lines.first.unitPrice,
            )
          else
            Row(
              children: [
                Expanded(child: _SummaryBox(title: 'إجمالي اللترات', value: preview == null ? '—' : '${groupThousands(preview.liters)} لتر', color: const Color(0xFFEFF6FF))),
                const SizedBox(width: 8),
                Expanded(child: _SummaryBox(title: 'الإيراد المطلوب', value: preview == null ? '—' : '${preview.expectedCash} د.ل', color: const Color(0xFFF8FAFC))),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryBox(
                    title: 'الفرق',
                    value: preview == null ? '—' : preview.phrase,
                    color: const Color(0xFFECFDF3),
                    emphasize: preview != null && preview.kind != 'match',
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('duty-cash'),
            controller: _cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ النقدي المسلّم فعلياً في الصندوق (د.ل)'),
            onChanged: (_) => setState(() {}),
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 8),
            Text(
              preview == null ? '—' : preview.phrase,
              key: const Key('duty-variance'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: preview != null && preview.kind != 'match' ? AppColors.error : AppColors.success,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('duty-submit'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), minimumSize: const Size.fromHeight(52)),
            onPressed: preview == null ? null : () => _confirm(context, preview),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('اعتماد الإغلاق النهائي وتسليم العهدة'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, DutyPreview preview) async {
    final cubit = context.read<DutyCubit>();
    await showAppDialog<void>(
      context: context,
      title: 'تأكيد إغلاق الوردية وتسليم العهدة',
      icon: Icons.fact_check_outlined,
      content: Text('${preview.phrase}\n${preview.expectedCash} د.ل'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () async {
            final saved = await cubit.submitClose(
              cash: _cash.text.trim(),
              lines: [
                for (final line in widget.duty.lines)
                  {
                    'nozzle_id': line.nozzleId,
                    'closing_meter': _closings[line.nozzleId]!.text.trim(),
                  },
              ],
            );
            if (!context.mounted) {
              return;
            }
            Navigator.pop(context);
            if (saved != null && context.mounted) {
              await showAppDialog<void>(
                context: context,
                title: 'تم رفع المحضر',
                icon: Icons.check_circle_outline,
                content: Text(saved.varianceLabel ?? 'بانتظار توقيع المشرف'),
                actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
              );
            }
          },
          child: const Text('نعم، اعتماد الإغلاق'),
        ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.state, required this.onShowHistory});

  final DutyState state;
  final VoidCallback? onShowHistory;

  @override
  Widget build(BuildContext context) {
    final rows = state.historyExpanded ? state.history : state.history.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'سجل الورديات السابقة الخاصة بالموظف (اعتماد العدادات والتسليم)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const Text('آخر 3 مناوبات معتمدة', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text('لا توجد ورديات سابقة.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                columns: const [
                  DataColumn(label: Text('التاريخ والوردية')),
                  DataColumn(label: Text('ساعات الدوام')),
                  DataColumn(label: Text('مضخات الوردية')),
                  DataColumn(label: Text('إجمالي اللترات')),
                  DataColumn(label: Text('الإيراد المحتسب')),
                  DataColumn(label: Text('النقدية المسلّمة')),
                  DataColumn(label: Text('المطابقة')),
                  DataColumn(label: Text('المشرف المعتمد')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(cells: [
                      DataCell(Text('${row.businessDate} (${row.statusLabel})')),
                      DataCell(Text(row.openedAt ?? '—')),
                      DataCell(Text(row.lines.map((line) => line.pumpCode).toSet().join(' و '))),
                      DataCell(Text(row.liters ?? '—')),
                      DataCell(Text(row.expectedCash ?? '—')),
                      DataCell(Text(row.cashHanded ?? '—')),
                      DataCell(Text(row.varianceLabel ?? '—')),
                      DataCell(Text(row.approvedByName ?? '—')),
                    ]),
                ],
              ),
            ),
          if (!state.historyExpanded && state.history.length > 3)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  context.read<DutyCubit>().showHistory();
                  onShowHistory?.call();
                },
                child: const Text('عرض السجل الكامل'),
              ),
            ),
        ],
      ),
    );
  }
}

class HistoryList extends StatelessWidget {
  const HistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = context.watch<DutyCubit>().state.history;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ScheduleBoard(),
        const SizedBox(height: 16),
        const Text('سجل الورديات السابقة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
        const SizedBox(height: 8),
        if (rows.isEmpty) const Text('لا توجد ورديات سابقة.'),
        for (final row in rows) _HistoryCard(row: row),
      ],
    );
  }
}

class ScheduleBoard extends StatelessWidget {
  const ScheduleBoard({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final name = session is SessionSignedIn ? session.user.fullName : '';
    final shifts = ShiftRoster.timetable();
    final today = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('جدول الورديات القادمة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 4),
          const Text(
            'المواعيد التي يربطها مدير المحطة من إعدادات الورديات تظهر هنا.',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (var offset = 0; offset < 4; offset++)
            for (final shift in shifts)
              _ScheduleRow(
                date: today.add(Duration(days: offset)),
                shift: shift,
                mine: shift.employeeNames.contains(name),
              ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.date, required this.shift, required this.mine});

  final DateTime date;
  final ShiftAssignment shift;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final label = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFFECFDF3) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label • ${shift.shiftName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(shift.window, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                Text(
                  shift.employeeNames.isEmpty ? 'بدون تكليف' : 'المكلفون: ${shift.employeeNames.join('، ')}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (mine)
            const Text('مجدول لك', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.row, this.mobile = false});

  final DutyRecord row;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    if (!mobile) {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${row.businessDate} • ${row.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('اللترات ${row.liters ?? '—'}'),
            Text('المتوقع ${row.expectedCash ?? '—'} • المسلم ${row.cashHanded ?? '—'}'),
            Text(row.varianceLabel ?? '—'),
            Text('المشرف: ${row.approvedByName ?? '—'}'),
          ],
        ),
      );
    }
    final matched = row.varianceLabel?.contains('مطابق') ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EEFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${row.businessDate} • ${row.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: matched ? const Color(0xFFECFDF3) : const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(99)),
                child: Text(matched ? 'مطابق ومعتمد' : 'معتمد', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: matched ? AppColors.success : AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('اللترات ${row.liters ?? '—'} • ${row.expectedCash ?? '—'} د.ل'),
          Text('المشرف: ${row.approvedByName ?? '—'}', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class AccountPane extends StatelessWidget {
  const AccountPane({super.key, this.photo, this.onPickPhoto});

  final Uint8List? photo;
  final VoidCallback? onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final user = session is SessionSignedIn ? session.user : null;
    if (user == null) {
      return const SizedBox.shrink();
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                height: 88,
                child: photo == null
                    ? const ColoredBox(
                        color: AppColors.primary,
                        child: Icon(Icons.person, color: Colors.white, size: 40),
                      )
                    : Image.memory(photo!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text('الرقم الوظيفي ${user.employeeCode}'),
                  Text(user.stationName),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onPickPhoto,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('إضافة صورة للحساب'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.read<SessionCubit>().signedOut(),
          child: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
}

class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.openedAt, this.large = false});

  final String openedAt;
  final bool large;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opened = DateTime.tryParse(widget.openedAt);
    if (opened == null) {
      return const SizedBox.shrink();
    }
    final elapsed = DateTime.now().toUtc().difference(opened.toUtc());
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final clock = '$hours:$minutes:$seconds';
    if (widget.large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('مدة العمل المنقضية', style: TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
          Text(clock, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      );
    }
    return Text('منذ بدء الوردية $clock');
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, this.emphasize = false});

  final String title;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            value,
            key: title == 'الفرق' ? const Key('duty-variance') : null,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: emphasize ? AppColors.error : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFFDCFCE7),
      child: Text(text, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
    );
  }
}
