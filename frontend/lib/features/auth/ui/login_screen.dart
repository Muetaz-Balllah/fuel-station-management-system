import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/logic/cubit/login_cubit.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/auth/ui/widgets/login_brand_panel.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.cubit});

  final LoginCubit? cubit;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(
        value: cubit!,
        child: const _LoginForm(),
      );
    }
    return BlocProvider(
      create: (_) => LoginCubit(getIt(), getIt<SessionCubit>()),
      child: const _LoginForm(),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _remember = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<LoginCubit>().submit(
          username: _username.text,
          password: _password.text,
          rememberMe: _remember,
        );
  }

  Future<void> _info(String title, String body) {
    return showAppDialog<void>(
      context: context,
      title: title,
      content: Text(body),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final form = _FormCard(
              username: _username,
              password: _password,
              obscure: _obscure,
              remember: _remember,
              onToggleObscure: () => setState(() => _obscure = !_obscure),
              onRemember: (value) => setState(() => _remember = value),
              onSubmit: _submit,
              onForgot: () => _info(
                'نسيت كلمة المرور؟',
                'لا يُرسل هذا الإصدار بريداً إلكترونياً. اطلب من مدير المحطة إعادة تعيين كلمة المرور.',
              ),
              onPrivacy: () => _info(
                'سياسة الخصوصية',
                'بيانات الدخول والحسابات تُحفظ داخل نظام المحطة ولا تُشارك مع طرف خارجي.',
              ),
              onHelp: () => _info(
                'مركز المساعدة',
                'للحصول على حساب أو إعادة تعيين كلمة المرور، راجع مدير المحطة.',
              ),
            );
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: form,
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: SizedBox(
                  height: 640,
                  child: Card(
                    elevation: 0,
                    color: AppColors.surfaceLowest,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: AppColors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        const Expanded(child: LoginBrandPanel()),
                        Expanded(child: SingleChildScrollView(child: form)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.username,
    required this.password,
    required this.obscure,
    required this.remember,
    required this.onToggleObscure,
    required this.onRemember,
    required this.onSubmit,
    required this.onForgot,
    required this.onPrivacy,
    required this.onHelp,
  });

  final TextEditingController username;
  final TextEditingController password;
  final bool obscure;
  final bool remember;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool> onRemember;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;
  final VoidCallback onPrivacy;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: BlocBuilder<LoginCubit, LoginState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تسجيل الدخول',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'مرحباً بك مجدداً، يرجى إدخال بياناتك للوصول إلى النظام',
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
              ),
              const SizedBox(height: 28),
              const Text(
                'اسم المستخدم',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('login-username'),
                controller: username,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'أدخل اسم المستخدم',
                  prefixIcon: Icon(Icons.person_outline, color: AppColors.onSurfaceVariant.withValues(alpha: 0.55)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'كلمة المرور',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('login-password'),
                controller: password,
                obscureText: obscure,
                obscuringCharacter: '•',
                style: TextStyle(
                  color: AppColors.onSurface,
                  letterSpacing: obscure ? 2 : 0,
                ),
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: 'أدخل كلمة المرور',
                  hintStyle: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.35),
                    letterSpacing: 2,
                    fontWeight: FontWeight.w300,
                  ),
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.onSurfaceVariant.withValues(alpha: 0.55)),
                  suffixIcon: IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: remember,
                    onChanged: (value) => onRemember(value ?? false),
                  ),
                  const Text('تذكرني'),
                  const Spacer(),
                  TextButton(
                    onPressed: onForgot,
                    child: const Text('نسيت كلمة المرور؟'),
                  ),
                ],
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  key: const Key('login-error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('login-submit'),
                  onPressed: state.submitting ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: state.submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'دخول إلى النظام',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.login),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                '© 2026 نظام إدارة الوقود المتكامل',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: onPrivacy, child: const Text('سياسة الخصوصية')),
                  const Text('•'),
                  TextButton(onPressed: onHelp, child: const Text('مركز المساعدة')),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
