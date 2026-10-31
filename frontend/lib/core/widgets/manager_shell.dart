import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/logic/cubit/notification_cubit.dart';
import 'package:frontend/features/auth/ui/widgets/change_password_dialog.dart';
import 'package:go_router/go_router.dart';

class ManagerShell extends StatelessWidget {
  const ManagerShell({super.key, this.child, this.location = '/manager', this.notifications});

  final Widget? child;
  final String location;
  final NotificationCubit? notifications;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionCubit>().state;
    final user = state is SessionSignedIn ? state.user : null;
    final assets = location.startsWith('/manager/assets');
    final supply = location.startsWith('/manager/supply');
    final attendance = location.startsWith('/manager/attendance');
    final shifts = location.startsWith('/manager/shifts');
    final settings = location.startsWith('/manager/settings');
    final title = assets
        ? 'إدارة الخزانات والمضخات'
        : supply
            ? 'إدارة التوريدات والموردين'
            : attendance
                ? 'سجل الحضور والدوام'
                : shifts
                    ? 'سجل كافة الورديات'
                    : settings
                        ? 'إعدادات النظام'
                        : 'لوحة التحكم';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _Sidebar(
            assetsSelected: assets,
            supplySelected: supply,
            attendanceSelected: attendance,
            shiftsSelected: shifts,
            settingsSelected: settings,
            onPassword: () => showDialog<void>(
              context: context,
              builder: (_) => const ChangePasswordDialog(),
            ),
            onLogout: () => context.read<SessionCubit>().signedOut(),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: title,
                  name: user?.fullName ?? '',
                  role: user?.roleNameAr ?? '',
                  initials: user?.initials ?? '',
                  notifications: notifications,
                ),
                Expanded(child: child ?? const ManagerHome()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ManagerHome extends StatelessWidget {
  const ManagerHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Align(
        alignment: Alignment.topRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'نظرة عامة على العمليات',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
            SizedBox(height: 8),
            Text(
              'مرحباً بك مجدداً، مدير المحطة. إليك ملخص أداء اليوم.',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.assetsSelected,
    required this.supplySelected,
    required this.attendanceSelected,
    required this.shiftsSelected,
    required this.settingsSelected,
    required this.onPassword,
    required this.onLogout,
  });

  final bool assetsSelected;
  final bool supplySelected;
  final bool attendanceSelected;
  final bool shiftsSelected;
  final bool settingsSelected;
  final VoidCallback onPassword;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.local_gas_station, color: Colors.white, size: 36),
          const SizedBox(height: 12),
          const Text(
            'إدارة الوقود',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const Text(
            'ليبيا - نظام الإدارة',
            style: TextStyle(color: Color(0xFF8392BC), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                _NavButton(
                  icon: Icons.dashboard,
                  label: 'لوحة القيادة',
                  selected: !assetsSelected && !supplySelected && !attendanceSelected && !shiftsSelected && !settingsSelected,
                  onTap: () => GoRouter.maybeOf(context)?.go('/manager'),
                ),
                _NavButton(
                  icon: Icons.local_gas_station,
                  label: 'الخزانات والمضخات',
                  selected: assetsSelected,
                  onTap: () => GoRouter.maybeOf(context)?.go('/manager/assets'),
                ),
                _NavButton(
                  icon: Icons.local_shipping_outlined,
                  label: 'التوريدات والموردين',
                  selected: supplySelected,
                  onTap: () => GoRouter.maybeOf(context)?.go('/manager/supply'),
                ),
                _NavButton(
            icon: Icons.fact_check_outlined,
            label: 'سجل الحضور والدوام',
            selected: attendanceSelected,
            onTap: () => GoRouter.maybeOf(context)?.go('/manager/attendance'),
          ),
          _NavButton(
            icon: Icons.receipt_long,
            label: 'سجل كافة الورديات',
            selected: shiftsSelected,
            onTap: () => GoRouter.maybeOf(context)?.go('/manager/shifts'),
          ),
                _NavButton(
                  icon: Icons.settings,
                  label: 'إعدادات النظام',
                  selected: settingsSelected,
                  onTap: () => GoRouter.maybeOf(context)?.go('/manager/settings'),
                ),
              ],
            ),
          ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
                onPressed: () => GoRouter.maybeOf(context)?.go('/manager/supply?new=1'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('طلب تزويد جديد'),
              ),
            ),
          ),
          TextButton(
            onPressed: onPassword,
            child: const Text('تغيير كلمة المرور', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _Bell extends StatefulWidget {
  const _Bell({required this.cubit});

  final NotificationCubit? cubit;

  @override
  State<_Bell> createState() => _BellState();
}

class _BellState extends State<_Bell> {
  @override
  void initState() {
    super.initState();
    widget.cubit?.load();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = widget.cubit;
    if (cubit == null) {
      return IconButton(
        onPressed: () => _open(context, const []),
        icon: const Icon(Icons.notifications_none),
      );
    }
    return BlocProvider.value(
      value: cubit,
      child: BlocBuilder<NotificationCubit, NotificationState>(
        builder: (context, state) {
          return IconButton(
            onPressed: () async {
              await _open(context, state.items);
              for (final item in state.items.where((item) => item.unread)) {
                await cubit.markRead(item.id);
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
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('التنبيهات'),
          content: items.isEmpty
              ? const Text('لا توجد تنبيهات')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${item.title}\n${item.body}'),
                      ),
                  ],
                ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
          ],
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.onSurface : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected ? const Color(0xFFE0E3E6) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.name,
    required this.role,
    required this.initials,
    required this.notifications,
  });

  final String title;
  final String name;
  final String role;
  final String initials;
  final NotificationCubit? notifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.circle, size: 8, color: AppColors.success),
          const SizedBox(width: 6),
          const Text('متصل', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
          const Spacer(),
          _Bell(cubit: notifications),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: AppColors.primaryContainer,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
