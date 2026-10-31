import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/logic/cubit/duty_cubit.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';

class DutyView extends StatelessWidget {
  const DutyView({super.key, this.onShowHistory});

  final VoidCallback? onShowHistory;

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
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          user == null ? '' : '${user.fullName} • ${user.employeeCode}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        if ((state.templateName ?? '').isNotEmpty)
          Text(state.templateName!, style: const TextStyle(color: AppColors.onSurfaceVariant)),
        if (state.duty?.openedAt != null) ...[
          const SizedBox(height: 8),
          _Elapsed(openedAt: state.duty!.openedAt!),
        ],
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
      ],
    );
  }
}

class _DesktopBody extends StatelessWidget {
  const _DesktopBody({required this.state, required this.onShowHistory});

  final DutyState state;
  final VoidCallback? onShowHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.duty == null)
          _OpenCard(state: state)
        else ...[
          _OpeningCard(duty: state.duty!),
          const SizedBox(height: 16),
          if (state.duty!.canClose) _CloseForm(duty: state.duty!) else _Waiting(duty: state.duty!),
        ],
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
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final duty = widget.state.duty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('فتح وردية جديدة')),
            ButtonSegment(value: 1, label: Text('إغلاق الوردية')),
          ],
          selected: {_segment},
          onSelectionChanged: (value) => setState(() => _segment = value.first),
        ),
        const SizedBox(height: 16),
        if (_segment == 0)
          duty == null ? _OpenCard(state: widget.state) : _OpeningCard(duty: duty)
        else if (duty == null)
          const Text('افتح الوردية أولاً ثم أدخل قراءات الإغلاق.')
        else if (duty.canClose)
          _CloseForm(duty: duty)
        else
          _Waiting(duty: duty),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: widget.onShowHistory,
          child: const Text('عرض السجل الكامل'),
        ),
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
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(child: Text('قراءات الافتتاح', style: TextStyle(fontWeight: FontWeight.w700))),
              _Chip(text: 'معتمد'),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in duty.lines)
            Text('${line.pumpCode} • ${line.nozzleCode} (${line.productName})  ${line.openingMeter}'),
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
  const _CloseForm({required this.duty});

  final DutyRecord duty;

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
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('إغلاق الوردية وتسليم العهدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (prices.length == 1)
            Text('${prices.first} د.ل / لتر', style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final line in widget.duty.lines) ...[
            Text('${line.pumpCode} • عداد الإغلاق ${line.nozzleCode} (${line.productName})'),
            TextField(
              key: Key('close-${line.nozzleId}'),
              controller: _closings[line.nozzleId],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'افتتاح ${line.openingMeter}'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('duty-cash'),
            controller: _cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'النقد المسلم'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Tile(title: 'اللترات', value: preview == null ? '—' : groupThousands(preview.liters)),
              _Tile(title: 'النقد المتوقع', value: preview == null ? '—' : '${preview.expectedCash} د.ل'),
              _Tile(
                title: 'الفرق',
                value: preview == null ? '—' : preview.phrase,
                emphasize: preview != null && preview.kind != 'match',
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('duty-submit'),
            onPressed: preview == null ? null : () => _confirm(context, preview),
            child: const Text('اعتماد الإغلاق النهائي وتسليم العهدة'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, DutyPreview preview) async {
    final cubit = context.read<DutyCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('تأكيد إغلاق الوردية وتسليم العهدة'),
          content: Text('${preview.phrase}\n${preview.expectedCash} د.ل'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
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
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                if (saved != null && context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (doneContext) {
                      return AlertDialog(
                        title: const Text('تم رفع المحضر'),
                        content: Text(saved.varianceLabel ?? 'بانتظار توقيع المشرف'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(doneContext), child: const Text('إغلاق')),
                        ],
                      );
                    },
                  );
                }
              },
              child: const Text('نعم، اعتماد الإغلاق'),
            ),
          ],
        );
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('سجل الورديات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (rows.isEmpty) const Text('لا توجد ورديات سابقة.'),
        for (final row in rows) _HistoryCard(row: row),
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
    );
  }
}

class HistoryList extends StatelessWidget {
  const HistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = context.watch<DutyCubit>().state.history;
    if (rows.isEmpty) {
      return const Center(child: Text('لا توجد ورديات سابقة.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final row in rows) _HistoryCard(row: row)],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.row});

  final DutyRecord row;

  @override
  Widget build(BuildContext context) {
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
}

class AccountPane extends StatelessWidget {
  const AccountPane({super.key});

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
        Text(user.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
        const SizedBox(height: 8),
        Text('الرقم الوظيفي ${user.employeeCode}'),
        Text(user.stationName),
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
  const _Elapsed({required this.openedAt});

  final String openedAt;

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
    return Text('منذ بدء الوردية $hours:$minutes:$seconds');
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
