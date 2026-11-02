import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 8) {
      setState(() => _error = 'كلمة المرور الجديدة يجب أن تكون 8 أحرف على الأقل.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await getIt<AuthGateway>().changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) {
        return;
      }
      await showAppDialog<void>(
        context: context,
        title: 'تم تغيير كلمة المرور',
        subtitle: 'سجّل الدخول من جديد بكلمة المرور الجديدة.',
        icon: Icons.check_circle_outline,
        content: const SizedBox.shrink(),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسناً'),
          ),
        ],
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      await context.read<SessionCubit>().signedOut();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.outlineVariant),
            boxShadow: const [BoxShadow(color: Color(0x26041539), blurRadius: 32, offset: Offset(0, 16))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: const Color(0xFFE7EEFF), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.key_outlined, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تغيير كلمة المرور', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          SizedBox(height: 4),
                          Text('احرص على اختيار كلمة مرور قوية لا تقل عن 8 أحرف.', style: TextStyle(color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _current,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'كلمة المرور الحالية'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _next,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('إلغاء')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('حفظ'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
