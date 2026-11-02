import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/widgets/notification_bell.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';
import 'package:frontend/features/dashboard/logic/cubit/notification_cubit.dart';
import 'package:dio/dio.dart';
import 'package:frontend/core/widgets/stored_image.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';
import 'package:frontend/features/shifts/logic/cubit/duty_cubit.dart';
import 'package:frontend/features/shifts/ui/duty_screen.dart';

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key, this.cubit, this.notifications});

  final DutyCubit? cubit;
  final NotificationCubit? notifications;

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  late final DutyCubit _cubit;
  late final NotificationCubit _notifications;
  late final bool _ownsCubit;
  late final bool _ownsNotifications;
  int _tab = 0;
  Uint8List? _photo;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _ownsCubit = widget.cubit == null;
    if (widget.notifications != null) {
      _notifications = widget.notifications!;
      _ownsNotifications = false;
    } else if (getIt.isRegistered<NotificationCubit>()) {
      _notifications = getIt<NotificationCubit>();
      _ownsNotifications = false;
    } else {
      _notifications = NotificationCubit(DashboardRepository(Dio()));
      _ownsNotifications = true;
    }
    if (widget.cubit != null) {
      _cubit = widget.cubit!;
    } else {
      _cubit = DutyCubit(getIt<ShiftRepository>())..load();
      _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _cubit.load());
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null || !mounted) {
      return;
    }
    setState(() => _photo = bytes);
    try {
      final user = await getIt<AuthGateway>().uploadPhoto(bytes: bytes, filename: result!.files.single.name);
      if (!mounted) {
        return;
      }
      context.read<SessionCubit>().signedIn(user);
      setState(() => _photo = null);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حفظ الصورة. حاول مرة أخرى.')));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_ownsCubit) {
      _cubit.close();
    }
    if (_ownsNotifications) {
      _notifications.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionCubit>().state;
    final user = state is SessionSignedIn ? state.user : null;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: wide
                  ? _DesktopHeader(user: user, photo: _photo, onPhoto: _pickPhoto, notifications: _notifications)
                  : _PhoneHeader(user: user, photo: _photo, notifications: _notifications),
            ),
            Expanded(
              child: IndexedStack(
                index: wide ? 0 : _tab,
                children: [
                  DutyView(photo: _photo, photoUrl: user?.photoUrl, onShowHistory: () => setState(() => _tab = 1)),
                  const HistoryList(),
                  AccountPane(photo: _photo, photoUrl: user?.photoUrl, onPickPhoto: _pickPhoto),
                ],
              ),
            ),
            if (wide)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('نظام FuelOps Libya — بوابة الموظف', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    Text('الإصدار التشغيلي 2.4 | متصل بالخادم المركزي', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (index) => setState(() => _tab = index),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.schedule), label: 'الوردية'),
                  NavigationDestination(icon: Icon(Icons.receipt_long), label: 'السجل'),
                  NavigationDestination(icon: Icon(Icons.person), label: 'حسابي'),
                ],
              ),
      ),
    );
  }
}

ImageProvider<Object>? _avatarImage(Uint8List? bytes, String? url) {
  if (bytes != null) {
    return MemoryImage(bytes);
  }
  final resolved = mediaUrl(url);
  if (resolved == null) {
    return null;
  }
  return NetworkImage(resolved);
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({required this.user, required this.photo, required this.notifications});

  final dynamic user;
  final Uint8List? photo;
  final NotificationCubit notifications;

  @override
  Widget build(BuildContext context) {
    final station = user == null ? 'محطة النور' : user.stationName as String;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFF041539), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.local_gas_station, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(station, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF041539))),
              const Text('Current Shift', style: TextStyle(fontSize: 12, color: Color(0xFF45464E))),
            ],
          ),
        ),
        NotificationBell(cubit: notifications),
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFF041539),
          backgroundImage: _avatarImage(photo, user?.photoUrl),
          child: photo == null && mediaUrl(user?.photoUrl) == null ? const Icon(Icons.person, color: Colors.white, size: 16) : null,
        ),
      ],
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.user,
    required this.photo,
    required this.onPhoto,
    required this.notifications,
  });

  final dynamic user;
  final Uint8List? photo;
  final VoidCallback onPhoto;
  final NotificationCubit notifications;

  @override
  Widget build(BuildContext context) {
    final name = user == null ? '' : user.fullName as String;
    final code = user == null ? '' : user.employeeCode as String;
    final station = user == null ? '' : '${user.stationName} (${user.stationCode})';
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFF0C1833), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.local_gas_station, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('نظام إدارة الوقود - ليبيا  |  بوابة مناوبة الموظف', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700)),
              Text(station, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF047857))),
            ],
          ),
        ),
        NotificationBell(cubit: notifications),
        InkWell(
          onTap: onPhoto,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF0F172A),
            backgroundImage: _avatarImage(photo, user?.photoUrl),
            child: photo == null && mediaUrl(user?.photoUrl) == null ? const Icon(Icons.person, color: Colors.white, size: 16) : null,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            Text('فني وردية ($code)', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => context.read<SessionCubit>().signedOut(),
          icon: const Icon(Icons.logout, size: 16),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
}
