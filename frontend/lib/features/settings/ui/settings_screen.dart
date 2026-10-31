import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/networking/api_config.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/features/settings/ui/widgets/license_banner.dart';
import 'package:frontend/features/settings/ui/widgets/shift_template_form.dart';

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
    final session = context.watch<SessionCubit>().state;
    final canEditRoles = session is SessionSignedIn && session.user.roleCode == 'system_admin';
    return ColoredBox(
      color: AppColors.background,
      child: DefaultTabController(
        length: 4,
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
                Tab(key: Key('tab-roles'), text: 'الأدوار والصلاحيات'),
                Tab(key: Key('tab-shifts'), text: 'إعدادات الورديات ومواعيد المناوبات'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _StationTab(state: state),
                  _UsersTab(state: state),
                  _RolesTab(state: state, canEdit: canEditRoles),
                  _ShiftsTab(state: state),
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
      padding: const EdgeInsets.all(24),
      children: [
        _StationForm(station: station),
        const SizedBox(height: 28),
        const Text('أسعار الوقود', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
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
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = result?.files.single;
    final path = file?.path;
    if (path == null || !mounted) {
      return;
    }
    await context.read<SettingsCubit>().uploadLogo(path, file!.name);
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
              child: logo == null
                  ? const Icon(Icons.local_gas_station, color: AppColors.primary, size: 40)
                  :                       Image.network(
                      '$apiBaseUrl$logo',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
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
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المحطة')),
        const SizedBox(height: 12),
        TextField(controller: _license, decoration: const InputDecoration(labelText: 'رقم الترخيص')),
        const SizedBox(height: 12),
        TextField(
          controller: _expires,
          decoration: const InputDecoration(labelText: 'تاريخ انتهاء الترخيص', hintText: '2027-12-31'),
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
                context.read<SettingsCubit>().addPrice(widget.product.id, value);
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'بحث',
                    hintText: 'الاسم أو اسم المستخدم',
                  ),
                  onSubmitted: (value) => context.read<SettingsCubit>().applyUserFilter(search: value),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: widget.state.roleFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('جميع الأدوار')),
                  DropdownMenuItem(value: 'station_manager', child: Text('مدير المحطة')),
                  DropdownMenuItem(value: 'operator', child: Text('موظف')),
                  DropdownMenuItem(value: 'maintenance', child: Text('فني صيانة')),
                  DropdownMenuItem(value: 'system_admin', child: Text('مدير النظام')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    context.read<SettingsCubit>().applyUserFilter(role: value);
                  }
                },
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _editUser(context, null),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('إضافة مستخدم جديد'),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.state.users.isEmpty
              ? const Center(child: Text('لا يوجد مستخدمون مطابقون.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: widget.state.users.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = widget.state.users[index];
                    return Opacity(
                      opacity: user.isActive ? 1 : 0.45,
                      child: ListTile(
                        title: Text('${user.fullName}  •  ${user.employeeCode}'),
                        subtitle: Text(
                          '${user.roleNameAr}${user.isMaintenance ? ' • فني صيانة' : ''} • ${user.email ?? 'بدون بريد'}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => _editUser(context, user),
                              child: const Text('تعديل'),
                            ),
                            TextButton(
                              onPressed: () => context.read<SettingsCubit>().updateUser(
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

  Future<void> _editUser(BuildContext context, StaffMember? user) async {
    final cubit = context.read<SettingsCubit>();
    final name = TextEditingController(text: user?.fullName ?? '');
    final username = TextEditingController(text: user?.username ?? '');
    final email = TextEditingController(text: user?.email ?? '');
    final job = TextEditingController(text: user?.jobTitle ?? '');
    final password = TextEditingController();
    var role = user?.roleCode ?? 'operator';
    var maintenance = user?.isMaintenance ?? false;
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(user == null ? 'إضافة مستخدم جديد' : 'تعديل المستخدم'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
                      TextField(controller: username, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
                      TextField(controller: email, decoration: const InputDecoration(labelText: 'البريد')),
                      TextField(controller: job, decoration: const InputDecoration(labelText: 'المسمى الوظيفي')),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: user == null ? 'كلمة المرور' : 'كلمة مرور جديدة (اختياري)',
                        ),
                      ),
                      DropdownButton<String>(
                        value: role,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'operator', child: Text('موظف')),
                          DropdownMenuItem(value: 'station_manager', child: Text('مدير المحطة')),
                          DropdownMenuItem(value: 'system_admin', child: Text('مدير النظام')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setLocal(() => role = value);
                          }
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('فني صيانة'),
                        value: maintenance,
                        onChanged: (value) => setLocal(() => maintenance = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: () async {
                    final body = <String, dynamic>{
                      'full_name': name.text.trim(),
                      'username': username.text.trim(),
                      'email': email.text.trim(),
                      'job_title': job.text.trim(),
                      'role_code': role,
                      'is_maintenance': maintenance,
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
        );
      },
    );
    name.dispose();
    username.dispose();
    email.dispose();
    job.dispose();
    password.dispose();
  }
}

class _RolesTab extends StatelessWidget {
  const _RolesTab({required this.state, required this.canEdit});

  final SettingsState state;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    if (state.roles.isEmpty) {
      return const Center(child: Text('لا توجد أدوار.'));
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          canEdit
              ? 'تعديل الصلاحيات يسري بعد تسجيل الدخول التالي.'
              : 'فقط مدير النظام يستطيع تعديل الصلاحيات.',
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final role in state.roles) _RoleCard(role: role, canEdit: canEdit),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.canEdit});

  final RoleGrant role;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(role.nameAr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final entry in permissionLabels.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entry.value),
                value: role.permissions.contains(entry.key),
                onChanged: canEdit
                    ? (checked) => context.read<SettingsCubit>().setPermission(
                          role,
                          entry.key,
                          checked ?? false,
                        )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftsTab extends StatelessWidget {
  const _ShiftsTab({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
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
        if (state.templates.isEmpty) const Text('لا توجد ورديات بعد.'),
        for (final template in state.templates)
          Card(
            child: ListTile(
              title: Text(template.nameAr),
              subtitle: Text(
                '${template.startsAt} – ${template.endsAt} • مهلة ${template.graceMinutes} د'
                '${template.crossesMidnight ? ' • تمتد لليوم التالي' : ''}'
                '${template.isActive ? '' : ' • متوقفة'}',
              ),
              trailing: TextButton(
                onPressed: () => _openForm(context, template),
                child: const Text('تعديل'),
              ),
            ),
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
}
