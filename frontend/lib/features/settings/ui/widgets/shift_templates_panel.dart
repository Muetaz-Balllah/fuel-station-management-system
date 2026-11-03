import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/layout/responsive_layout.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/shift_roster.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/features/settings/ui/widgets/shift_template_form.dart';

class ShiftTemplatesPanel extends StatelessWidget {
  const ShiftTemplatesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsCubit>().state;
    return ListView(
      padding: managerPagePadding(context),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const heading = Text(
              'إعدادات الورديات ومواعيد المناوبات',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            );
            final addButton = FilledButton.icon(
              key: const Key('shift-add'),
              onPressed: () => _openForm(context, null),
              icon: const Icon(Icons.add),
              label: const Text('إضافة وردية'),
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 12), addButton],
              );
            }
            return Row(
              children: [
                const Expanded(child: heading),
                addButton,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'قوالب الورديات النشطة في المحطة — المواعيد والربط بالموظفين يظهران أدناه. الورديات المنتهية تُغلق تلقائياً في جدول التشغيل.',
          style: TextStyle(color: AppColors.onSurfaceVariant, height: 1.5),
        ),
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
            width: managerDialogWidth(context, preferred: 420),
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

class _ShiftChip extends StatelessWidget {
  const _ShiftChip({required this.icon, required this.label, this.highlight = false});

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFE7EEFF) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: highlight ? AppColors.primary : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: highlight ? AppColors.primary : AppColors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: highlight ? AppColors.primary : AppColors.onSurface)),
        ],
      ),
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
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 560;
                    final titleBlock = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(template.nameAr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ShiftChip(icon: Icons.schedule, label: '${template.startsAt} – ${template.endsAt}'),
                            _ShiftChip(icon: Icons.timer_outlined, label: 'مهلة ${template.graceMinutes} د'),
                            if (template.crossesMidnight) const _ShiftChip(icon: Icons.nightlight_round, label: 'تمتد لليوم التالي'),
                            _ShiftChip(
                              icon: template.isActive ? Icons.check_circle_outline : Icons.pause_circle_outline,
                              label: template.isActive ? 'نشطة في الجدول' : 'متوقفة',
                              highlight: template.isActive,
                            ),
                          ],
                        ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 4,
                      children: [
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
                    );
                    if (narrow) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [titleBlock, actions]);
                    }
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: titleBlock), actions]);
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('هيكل الربط والموظفون', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        crew.isEmpty ? 'لم يُربط موظفون بعد — استخدم الزر أدناه لتحديد مناوبي هذه الوردية.' : crew.join(' • '),
                        style: const TextStyle(color: AppColors.onSurfaceVariant, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
