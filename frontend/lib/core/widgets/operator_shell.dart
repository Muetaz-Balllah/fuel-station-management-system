import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/auth/ui/widgets/change_password_dialog.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';
import 'package:frontend/features/shifts/logic/cubit/duty_cubit.dart';
import 'package:frontend/features/shifts/ui/duty_screen.dart';

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key, this.cubit});

  final DutyCubit? cubit;

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  late final DutyCubit _cubit;
  late final bool _ownsCubit;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _ownsCubit = widget.cubit == null;
    if (widget.cubit != null) {
      _cubit = widget.cubit!;
    } else {
      _cubit = DutyCubit(getIt<ShiftRepository>())..load();
    }
  }

  @override
  void dispose() {
    if (_ownsCubit) {
      _cubit.close();
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
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1833),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_gas_station, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'نظام إدارة الوقود - ليبيا',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      user?.fullName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'تغيير كلمة المرور',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ChangePasswordDialog(),
                    ),
                    icon: const Icon(Icons.key_outlined),
                  ),
                  IconButton(
                    tooltip: 'تسجيل الخروج',
                    onPressed: () => context.read<SessionCubit>().signedOut(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: wide ? 0 : _tab,
                children: [
                  DutyView(onShowHistory: () => setState(() => _tab = 1)),
                  const HistoryList(),
                  const AccountPane(),
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
