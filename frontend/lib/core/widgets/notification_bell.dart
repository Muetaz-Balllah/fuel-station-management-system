import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/logic/cubit/notification_cubit.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.cubit});

  final NotificationCubit cubit;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    widget.cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.cubit,
      child: BlocBuilder<NotificationCubit, NotificationState>(
        builder: (context, state) {
          return IconButton(
            tooltip: 'التنبيهات',
            onPressed: () async {
              await _open(context, state.items);
              for (final item in state.items.where((item) => item.unread)) {
                await widget.cubit.markRead(item.id);
              }
            },
            icon: Badge(
              isLabelVisible: state.unread > 0,
              child: const Icon(Icons.notifications_none),
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(BuildContext context, List<StationNotice> items) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    return showAppDialog<void>(
      context: context,
      title: 'التنبيهات',
      icon: Icons.notifications_outlined,
      width: 520,
      content: items.isEmpty
          ? const Text('لا توجد تنبيهات')
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.unread ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: item.unread ? const Color(0xFFFDBA74) : AppColors.outlineVariant,
                      ),
                    ),
                    child: Text('${item.title}\n${item.body}'),
                  );
                },
              ),
            ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق'))],
    );
  }
}
