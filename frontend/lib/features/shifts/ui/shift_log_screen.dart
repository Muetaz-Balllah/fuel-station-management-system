import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';
import 'package:frontend/features/shifts/logic/cubit/shift_log_cubit.dart';

class ShiftLogScreen extends StatelessWidget {
  const ShiftLogScreen({super.key, this.cubit});

  final ShiftLogCubit? cubit;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(value: cubit!, child: const ShiftLogView());
    }
    return BlocProvider(
      create: (_) => ShiftLogCubit(getIt<ShiftRepository>())..load(),
      child: const ShiftLogView(),
    );
  }
}

class ShiftLogView extends StatelessWidget {
  const ShiftLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftLogCubit>().state;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'سجل كافة الورديات',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(state.error!, key: const Key('shift-error'), style: const TextStyle(color: AppColors.error)),
          ),
        const SizedBox(height: 16),
        if (state.rows.isEmpty)
          const Text('لا توجد ورديات في هذا المدى.')
        else
          for (final row in state.rows)
            ListTile(
              selected: row.id == state.selectedId,
              onTap: () => context.read<ShiftLogCubit>().select(row.id),
              title: Text('${row.code} • ${row.window}'),
              subtitle: Text(
                '${row.businessDate} • ${row.supervisor.isEmpty ? '—' : row.supervisor}\n'
                '${row.liters ?? '—'} لتر • ${row.revenue ?? '—'} • ${row.varianceLabel ?? '—'} • ${row.statusLabel}',
              ),
            ),
        const SizedBox(height: 16),
        for (final duty in state.duties) _DutyActions(duty: duty),
      ],
    );
  }
}

class _DutyActions extends StatelessWidget {
  const _DutyActions({required this.duty});

  final DutyRecord duty;

  @override
  Widget build(BuildContext context) {
    final pending = duty.status == 'pending_approval';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${duty.fullName} • ${duty.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${duty.liters ?? '—'} لتر • ${duty.expectedCash ?? '—'} • ${duty.varianceLabel ?? '—'}'),
          if (pending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: Key('duty-approve-${duty.id}'),
                  onPressed: () => context.read<ShiftLogCubit>().approve(duty.id),
                  child: const Text('اعتماد'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: Key('duty-reject-${duty.id}'),
                  onPressed: () => _reject(context),
                  child: const Text('رفض'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final cubit = context.read<ShiftLogCubit>();
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('رفض الوردية'),
          content: TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'سبب الرفض'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final ok = await cubit.reject(duty.id, reason.text);
                if (ok && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('رفض'),
            ),
          ],
        );
      },
    );
    reason.dispose();
  }
}
