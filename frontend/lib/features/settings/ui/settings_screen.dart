import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/layout/responsive_layout.dart';
import 'package:frontend/core/widgets/dispose_controllers.dart';
import 'package:frontend/core/widgets/stored_image.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/auth/ui/widgets/change_password_dialog.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/features/settings/ui/widgets/license_banner.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.cubit});

  final SettingsCubit? cubit;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(value: cubit!, child: const SettingsView());
    }
    return BlocProvider(
      create: (_) => SettingsCubit(getIt<SettingsRepository>())..load(),
      child: const SettingsView(),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsCubit>().state;
    return ColoredBox(
      color: AppColors.background,
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.error != null)
              MaterialBanner(
                content: Text(state.error!),
                backgroundColor: const Color(0xFFFFEDEA),
                actions: [
                  TextButton(
                    onPressed: () => context.read<SettingsCubit>().load(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            const TabBar(
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.outline,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(key: Key('tab-station'), text: 'إعدادات المحطة'),
                Tab(key: Key('tab-users'), text: 'إدارة المستخدمين'),
                Tab(key: Key('tab-account'), text: 'حسابي'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _StationTab(state: state),
                  _UsersTab(state: state),
                  const _AccountTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationTab extends StatelessWidget {
  const _StationTab({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final station = state.station;
    if (station == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: managerPagePadding(context),
      children: [
        _StationForm(station: station),
        const SizedBox(height: 28),
        const Text(
          'أسعار الوقود',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'تسجيل سعر جديد يبقي السعر السابق محفوظاً.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final product in state.products) _PriceRow(product: product),
      ],
    );
  }
}

class _StationForm extends StatefulWidget {
  const _StationForm({required this.station});

  final StationProfile station;

  @override
  State<_StationForm> createState() => _StationFormState();
}

class _StationFormState extends State<_StationForm> {
  late final TextEditingController _name;
  late final TextEditingController _license;
  late final TextEditingController _expires;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _license = TextEditingController();
    _expires = TextEditingController();
    _latitude = TextEditingController();
    _longitude = TextEditingController();
    _fill(widget.station);
  }

  @override
  void didUpdateWidget(covariant _StationForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != widget.station.id ||
        oldWidget.station.licenseNumber != widget.station.licenseNumber ||
        oldWidget.station.name != widget.station.name ||
        oldWidget.station.logoUrl != widget.station.logoUrl) {
      _fill(widget.station);
      if (oldWidget.station.logoUrl != widget.station.logoUrl) {
        _logoBytes = null;
      }
    }
  }

  void _fill(StationProfile station) {
    _name.text = station.name;
    _license.text = station.licenseNumber;
    _expires.text = station.licenseExpiresOn;
    _latitude.text = station.latitude?.toString() ?? '';
    _longitude.text = station.longitude?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _license.dispose();
    _expires.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || !mounted) {
      return;
    }
    setState(() => _logoBytes = bytes);
    final ok = await context.read<SettingsCubit>().uploadLogo(
      bytes: bytes,
      filename: file!.name,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      setState(() => _logoBytes = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.station.logoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: StoredImage(
                url: logo,
                bytes: _logoBytes,
                fit: BoxFit.contain,
                placeholder: const Icon(
                  Icons.local_gas_station,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.upload_file),
              label: const Text('رفع الشعار'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LicenseRenewalBanner(expiresOn: widget.station.licenseExpiresOn),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم المحطة'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _license,
          decoration: const InputDecoration(labelText: 'رقم الترخيص'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _expires,
          decoration: const InputDecoration(
            labelText: 'تاريخ انتهاء الترخيص',
            hintText: '2027-12-31',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _latitude,
                decoration: const InputDecoration(labelText: 'خط العرض'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _longitude,
                decoration: const InputDecoration(labelText: 'خط الطول'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: () => context.read<SettingsCubit>().saveStation(
                name: _name.text,
                licenseNumber: _license.text,
                licenseExpiresOn: _expires.text,
                latitude: _latitude.text,
                longitude: _longitude.text,
              ),
              child: const Text('حفظ'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => _fill(widget.station),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PriceRow extends StatefulWidget {
  const _PriceRow({required this.product});

  final FuelProductItem product;

  @override
  State<_PriceRow> createState() => _PriceRowState();
}

class _PriceRowState extends State<_PriceRow> {
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController();
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.product.activePrice ?? '—';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text('${widget.product.nameAr}  •  السعر الحالي $current'),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'سعر جديد'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'تسجيل السعر',
              onPressed: () {
                final value = _price.text.trim();
                if (value.isEmpty) {
                  return;
                }
                context.read<SettingsCubit>().addPrice(
                  widget.product.id,
                  value,
                );
                _price.clear();
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.state});

  final SettingsState state;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.state.userQuery);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pagePad = managerPagePadding(context);
    return Column(
      children: [
        Padding(
          padding: pagePad.copyWith(top: 16, bottom: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'بحث',
                  hintText: 'الاسم أو اسم المستخدم',
                ),
                onSubmitted: (value) => context
                    .read<SettingsCubit>()
                    .applyUserFilter(search: value),
              );
              final roleFilter = DropdownButton<String>(
                value: widget.state.roleFilter,
                isExpanded: constraints.maxWidth < 720,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('الجميع')),
                  DropdownMenuItem(
                    value: 'station_manager',
                    child: Text('مدير المحطة'),
                  ),
                  DropdownMenuItem(
                    value: 'operator',
                    child: Text('مشغل الوردية'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    context.read<SettingsCubit>().applyUserFilter(role: value);
                  }
                },
              );
              final addUser = FilledButton.icon(
                onPressed: () => _editUser(context, null),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('إضافة مستخدم جديد'),
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 12),
                    roleFilter,
                    const SizedBox(height: 12),
                    addUser,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  roleFilter,
                  const SizedBox(width: 12),
                  addUser,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: widget.state.users.isEmpty
              ? const Center(child: Text('لا يوجد مستخدمون مطابقون.'))
              : ListView.separated(
                  padding: pagePad.copyWith(top: 8),
                  itemCount: widget.state.users.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = widget.state.users[index];
                    return Opacity(
                      opacity: user.isActive ? 1 : 0.45,
                      child: ListTile(
                        leading: ClipOval(
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: StoredImage(
                              url: user.photoUrl,
                              placeholder: const ColoredBox(
                                color: AppColors.primary,
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          '${user.fullName}  •  ${user.employeeCode}',
                        ),
                        subtitle: Text(
                          '${user.roleNameAr}${user.isMaintenance ? ' • فني صيانة' : ''} • ${user.email ?? 'بدون بريد'}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => _pickUserPhoto(context, user),
                              child: const Text('صورة'),
                            ),
                            TextButton(
                              onPressed: () => _editUser(context, user),
                              child: const Text('تعديل'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  context.read<SettingsCubit>().updateUser(
                                    user.id,
                                    {'is_active': !user.isActive},
                                  ),
                              child: Text(user.isActive ? 'إيقاف' : 'استعادة'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _pickUserPhoto(BuildContext context, StaffMember user) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !context.mounted) {
      return;
    }
    final ok = await context.read<SettingsCubit>().uploadUserPhoto(
      userId: user.id,
      bytes: bytes,
      filename: file.name,
    );
    if (!ok || !context.mounted) {
      return;
    }
    final session = context.read<SessionCubit>().state;
    if (session is SessionSignedIn && session.user.id == user.id) {
      final refreshed = await getIt<AuthGateway>().restore();
      if (refreshed != null && context.mounted) {
        context.read<SessionCubit>().signedIn(refreshed);
      }
    }
  }

  Future<void> _editUser(BuildContext context, StaffMember? user) async {
    final cubit = context.read<SettingsCubit>();
    final name = TextEditingController(text: user?.fullName ?? '');
    final username = TextEditingController(text: user?.username ?? '');
    final email = TextEditingController(text: user?.email ?? '');
    final job = TextEditingController(text: user?.jobTitle ?? '');
    final password = TextEditingController();
    var role = user?.roleCode == 'station_manager'
        ? 'station_manager'
        : 'operator';
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return DisposeControllers(
          controllers: [name, username, email, job, password],
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return AlertDialog(
                title: Text(
                  user == null ? 'إضافة مستخدم جديد' : 'تعديل المستخدم',
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'الاسم'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: username,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: email,
                          decoration: const InputDecoration(
                            labelText: 'البريد',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: job,
                          decoration: const InputDecoration(
                            labelText: 'المسمى الوظيفي',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: user == null
                                ? 'كلمة المرور'
                                : 'كلمة مرور جديدة (اختياري)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButton<String>(
                          value: role,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'operator',
                              child: Text('مشغل الوردية'),
                            ),
                            DropdownMenuItem(
                              value: 'station_manager',
                              child: Text('مدير المحطة'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setLocal(() => role = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final body = <String, dynamic>{
                        'full_name': name.text.trim(),
                        'username': username.text.trim(),
                        'email': email.text.trim(),
                        'job_title': job.text.trim(),
                        'role_code': role,
                        'is_maintenance': false,
                      };
                      if (password.text.isNotEmpty) {
                        body['password'] = password.text;
                      }
                      final ok = user == null
                          ? await cubit.createUser(body)
                          : await cubit.updateUser(user.id, body);
                      if (ok && dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    child: const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final user = session is SessionSignedIn ? session.user : null;
    return ListView(
      padding: managerPagePadding(context),
      children: [
        const Text(
          'إعدادات الحساب',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'النظام يقتصر على دورين ثابتين: مدير المحطة ومشغل الوردية.',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        if (user != null) ...[
          const SizedBox(height: 16),
          Text(
            user.fullName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(user.roleCode == 'operator' ? 'مشغل الوردية' : 'مدير المحطة'),
        ],
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ChangePasswordDialog(),
            ),
            icon: const Icon(Icons.key_outlined),
            label: const Text('تغيير كلمة المرور'),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => context.read<SessionCubit>().signedOut(),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
        ),
      ],
    );
  }
}
