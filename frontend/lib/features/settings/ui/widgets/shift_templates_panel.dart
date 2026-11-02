import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/shift_roster.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/features/settings/ui/widgets/shift_day_schedule_panel.dart';
import 'package:frontend/features/settings/ui/widgets/shift_template_form.dart';

class ShiftTemplatesPanel extends StatelessWidget {
  const ShiftTemplatesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsCubit>().state;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'إعدادات الورديات ومواعيد المناوبات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              key: const Key('shift-add'),
              onPressed: () => _openForm(context, null),
              icon: const Icon(Icons.add),
              label: const Text('إضافة وردية'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const ShiftDaySchedulePanel(),
        const SizedBox(height: 16),
        if (state.templates.isEmpty) const Text('لا توجد ورديات بعد.'),
        for (final template in state.templates)
          _ShiftTemplateCard(
            template: template,
            employees: state.users.where((user) => user.isActive && user.roleCode == 'operator').toList(),
            onEdit: () => _openForm(context, template),
            onDelete: () => _confirmDelete(context, template),
          ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context, ShiftTemplateItem? existing) async {
    final cubit = context.read<SettingsCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(existing == null ? 'إضافة وردية' : 'تعديل الوردية'),
          content: SizedBox(
            width: 420,
            child: ShiftTemplateForm(
              existing: existing,
              onSubmit: (draft) async {
                final ok = await cubit.saveTemplate(draft, id: existing?.id);
                if (ok && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, ShiftTemplateItem template) async {
    final cubit = context.read<SettingsCubit>();
    await showAppDialog<void>(
      context: context,
      title: 'حذف الوردية',
      icon: Icons.delete_outline,
      content: Text('هل تريد حذف «${template.nameAr}» نهائياً؟ لا يمكن التراجع.'),
      actionsBuilder: (dialogContext) => [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
        FilledButton(
          key: Key('shift-delete-${template.id}'),
          onPressed: () async {
            final message = await cubit.deleteTemplate(template.id);
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
            if (message != null && context.mounted) {
              await showAppDialog<void>(
                context: context,
                title: 'تعذّر الحذف',
                icon: Icons.error_outline,
                content: Text(message),
                actionsBuilder: (ctx) => [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
              );
            }
          },
          child: const Text('حذف'),
        ),
      ],
    );
  }
}

class _ShiftTemplateCard extends StatelessWidget {
  const _ShiftTemplateCard({
    required this.template,
    required this.employees,
    required this.onEdit,
    required this.onDelete,
  });

  final ShiftTemplateItem template;
  final List<StaffMember> employees;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ShiftRoster.updates,
      builder: (context, _) {
        final crew = ShiftRoster.of(template.id)?.employeeNames ?? const <String>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(template.nameAr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            '${template.startsAt} – ${template.endsAt} • مهلة ${template.graceMinutes} د'
                            '${template.crossesMidnight ? ' • تمتد لليوم التالي' : ''}'
                            '${template.isActive ? '' : ' • متوقفة'}',
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: template.isActive,
                      onChanged: (value) {
                        context.read<SettingsCubit>().saveTemplate(
                              ShiftDraft(
                                nameAr: template.nameAr,
                                startsAt: template.startsAt,
                                endsAt: template.endsAt,
                                graceMinutes: template.graceMinutes,
                                isActive: value,
                              ),
                              id: template.id,
                            );
                      },
                    ),
                    TextButton(onPressed: onEdit, child: const Text('تعديل')),
                    IconButton(
                      key: Key('shift-delete-btn-${template.id}'),
                      tooltip: 'حذف الوردية',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  crew.isEmpty ? 'لا يوجد موظفون مرتبطون بهذه الوردية.' : 'الموظفون المكلفون: ${crew.join('، ')}',
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _assign(context),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('ربط الموظفين بالوردية'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _assign(BuildContext context) async {
    final selected = {...?ShiftRoster.of(template.id)?.employeeNames};
    final manual = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('تكليف موظفين — ${template.nameAr}'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('اختر مشغلي الوردية الذين سيظهر لهم هذا الموعد في جدولهم.'),
                      const SizedBox(height: 8),
                      if (employees.isEmpty)
                        const Text('لا يوجد مشغلو وردية مسجلون بعد. أضف اسماً يدوياً.')
                      else
                        for (final employee in employees)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${employee.fullName} • ${employee.employeeCode}'),
                            value: selected.contains(employee.fullName),
                            onChanged: (checked) {
                              setLocal(() {
                                if (checked ?? false) {
                                  selected.add(employee.fullName);
                                } else {
                                  selected.remove(employee.fullName);
                                }
                              });
                            },
                          ),
                      TextField(
                        controller: manual,
                        decoration: const InputDecoration(labelText: 'اسم موظف إضافي'),
                        onSubmitted: (value) {
                          final name = value.trim();
                          if (name.isEmpty) {
                            return;
                          }
                          setLocal(() => selected.add(name));
                          manual.clear();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: () {
                    final extra = manual.text.trim();
                    if (extra.isNotEmpty) {
                      selected.add(extra);
                    }
                    ShiftRoster.save(
                      ShiftAssignment(
                        templateId: template.id,
                        shiftName: template.nameAr,
                        window: '${template.startsAt} – ${template.endsAt}',
                        employeeNames: selected.toList(),
                      ),
                    );
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('حفظ التكليف'),
                ),
              ],
            );
          },
        );
      },
    );
    manual.dispose();
  }
}
