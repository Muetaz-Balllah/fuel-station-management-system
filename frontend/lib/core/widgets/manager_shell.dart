import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/dashboard/logic/cubit/notification_cubit.dart';
import 'package:frontend/core/widgets/notification_bell.dart';
import 'package:frontend/core/widgets/stored_image.dart';
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
    final settings = location.startsWith('/manager/settings');
    final title = assets
        ? 'إدارة الخزانات والمضخات'
        : supply
            ? 'إدارة التوريدات والموردين'
            : attendance
                ? 'الحضور والورديات'
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
            settingsSelected: settings,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  title: title,
                  name: user?.fullName ?? '',
                  role: user?.roleNameAr ?? '',
                  initials: user?.initials ?? '',
                  photoUrl: user?.photoUrl,
                  notifications: notifications,
                ),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.assetsSelected,
    required this.supplySelected,
    required this.attendanceSelected,
    required this.settingsSelected,
  });

  final bool assetsSelected;
  final bool supplySelected;
  final bool attendanceSelected;
  final bool settingsSelected;

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
                  selected: !assetsSelected && !supplySelected && !attendanceSelected && !settingsSelected,
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
            label: 'الحضور والورديات',
            selected: attendanceSelected,
            onTap: () => GoRouter.maybeOf(context)?.go('/manager/attendance'),
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
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFDBCC),
                  foregroundColor: const Color(0xFF7A3000),
                ),
                onPressed: () => GoRouter.maybeOf(context)?.go('/manager/supply?new=1'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('طلب تزويد جديد'),
              ),
            ),
          ),
        ],
      ),
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
    required this.photoUrl,
    required this.notifications,
  });

  final String title;
  final String name;
  final String role;
  final String initials;
  final String? photoUrl;
  final NotificationCubit? notifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(left: 280),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.ltr,
              children: [
                if (notifications != null) NotificationBell(cubit: notifications!),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: AppColors.primaryContainer,
                  backgroundImage: mediaUrl(photoUrl) == null ? null : NetworkImage(mediaUrl(photoUrl)!),
                  child: mediaUrl(photoUrl) == null
                      ? Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12))
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
