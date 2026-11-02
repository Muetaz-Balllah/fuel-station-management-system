import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';
import 'package:frontend/features/supply/data/models/supply_models.dart';
import 'package:frontend/features/supply/data/repos/supply_repository.dart';
import 'package:frontend/core/widgets/pagination_bar.dart';
import 'package:frontend/core/widgets/stored_image.dart';
import 'package:frontend/features/supply/logic/cubit/supply_cubit.dart';

class SupplyScreen extends StatelessWidget {
  const SupplyScreen({super.key, this.cubit, this.openCreate = false});

  final SupplyCubit? cubit;
  final bool openCreate;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(value: cubit!, child: SupplyView(openCreate: openCreate));
    }
    return BlocProvider(
      create: (_) => SupplyCubit(getIt<SupplyRepository>())..load(),
      child: SupplyView(openCreate: openCreate),
    );
  }
}

class SupplyView extends StatefulWidget {
  const SupplyView({super.key, this.openCreate = false});

  final bool openCreate;

  @override
  State<SupplyView> createState() => _SupplyViewState();
}

class _SupplyViewState extends State<SupplyView> {
  var _opened = false;
  final Map<String, Uint8List> _logos = {};

  @override
  void initState() {
    super.initState();
    if (widget.openCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOnce());
    }
  }

  Future<void> _pickLogo(String supplierId) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || !mounted) {
      return;
    }
    setState(() => _logos[supplierId] = bytes);
    final ok = await context.read<SupplyCubit>().uploadLogo(supplierId: supplierId, bytes: bytes, filename: file!.name);
    if (!mounted) {
      return;
    }
    if (ok) {
      setState(() => _logos.remove(supplierId));
    }
  }

  void _openOnce() {
    if (!mounted || _opened) {
      return;
    }
    final state = context.read<SupplyCubit>().state;
    if (!state.loaded) {
      return;
    }
    _opened = true;
    _create(context, state);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SupplyCubit>().state;
    if (widget.openCreate && state.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOnce());
    }
    final supplier = _selected(state);
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Counter(title: 'اجمالي الطلبات النشطة', value: '${state.activeOrders}'),
              _Counter(title: 'قيد الانتظار', value: '${state.pendingOrders}'),
              _Counter(title: 'الكمية الموردة (لتر)', value: _compact(state.deliveredLiters)),
              _Counter(title: 'الموردين النشطين', value: '${state.activeSuppliers}'),
            ],
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(state.error!, key: const Key('supply-error'), style: const TextStyle(color: AppColors.error)),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('supply-create'),
                  onPressed: state.loaded ? () => _create(context, state) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('إنشاء طلب توريد جديد'),
                ),
                OutlinedButton.icon(
                  key: const Key('supply-add-supplier'),
                  onPressed: state.loaded ? () => _addSupplier(context) : null,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('إضافة شركة توريد جديدة'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final orders = _OrdersPanel(
                orders: state.orders,
                page: state.ordersPage,
                pageCount: state.ordersPageCount,
                total: state.ordersTotal,
                onPage: (page) => context.read<SupplyCubit>().setOrdersPage(page),
              );
              final details = _SupplierColumn(
                state: state,
                supplier: supplier,
                logo: supplier == null ? null : _logos[supplier.id],
                onPickLogo: supplier == null ? null : () => _pickLogo(supplier.id),
              );
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [orders, const SizedBox(height: 16), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(flex: 3, child: orders),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Widget _logoPlaceholder(String name) {
  return ColoredBox(
    color: const Color(0xFFE7EEFF),
    child: Center(
      child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
    ),
  );
}

SupplierRecord? _selected(SupplyState state) {
  if (state.suppliers.isEmpty) {
    return null;
  }
  for (final item in state.suppliers) {
    if (item.id == state.selectedSupplierId) {
      return item;
    }
  }
  return state.suppliers.first;
}

class _Counter extends StatelessWidget {
  const _Counter({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _OrdersPanel extends StatelessWidget {
  const _OrdersPanel({
    required this.orders,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPage,
  });

  final List<SupplyOrderRecord> orders;
  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('سجل طلبات التوريد الأخيرة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primary)),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Text('لا توجد طلبات توريد.')
          else
            for (final order in orders) _OrderRow(order: order),
          PaginationBar(page: page, pageCount: pageCount, total: total, onPage: onPage),
        ],
      ),
    );
  }
}

class _SupplierColumn extends StatelessWidget {
  const _SupplierColumn({
    required this.state,
    required this.supplier,
    required this.logo,
    required this.onPickLogo,
  });

  final SupplyState state;
  final SupplierRecord? supplier;
  final Uint8List? logo;
  final VoidCallback? onPickLogo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.suppliers.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in state.suppliers)
                  ChoiceChip(
                    label: Text(item.name),
                    selected: item.id == supplier?.id,
                    onSelected: (_) => context.read<SupplyCubit>().selectSupplier(item.id),
                  ),
              ],
            ),
          ),
        if (supplier != null) _SupplierCard(supplier: supplier!, logo: logo, onPickLogo: onPickLogo),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('نشاط التوريد الأسبوعي', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _WeekBars(days: state.week),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final SupplyOrderRecord order;

  @override
  Widget build(BuildContext context) {
    final color = order.status == 'pending'
        ? AppColors.warning
        : order.status == 'received'
            ? AppColors.primary
            : const Color(0xFF75777F);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text('#${order.code}')),
          Expanded(child: Text(order.supplierName)),
          Expanded(child: Text(order.productName)),
          SizedBox(width: 90, child: Text(_compact(order.orderedLiters))),
          SizedBox(
            width: 110,
            child: Text(
              order.statusLabel,
              key: Key('order-status-${order.id}'),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: 100, child: Text(order.expectedOn)),
          if (order.status == 'pending') ...[
            TextButton(
              key: Key('order-receive-${order.id}'),
              onPressed: () => context.read<SupplyCubit>().receive(order.id),
              child: const Text('استلام'),
            ),
            TextButton(
              key: Key('order-cancel-${order.id}'),
              onPressed: () => context.read<SupplyCubit>().cancel(order.id),
              child: const Text('إلغاء'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier, required this.logo, required this.onPickLogo});

  final SupplierRecord supplier;
  final Uint8List? logo;
  final VoidCallback? onPickLogo;

  @override
  Widget build(BuildContext context) {
    final score = supplier.reliability == null ? '—' : '${supplier.reliability}%';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تفاصيل المورد', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: StoredImage(
                bytes: logo,
                url: supplier.logoUrl,
                placeholder: _logoPlaceholder(supplier.name),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPickLogo,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('إضافة شعار الشركة'),
          ),
          const SizedBox(height: 8),
          Text(supplier.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary)),
          Text('المقر الرئيسي: ${supplier.headquarters}', key: const Key('supplier-headquarters')),
          Text('سعة التوريد القصوى: ${_compact(supplier.maxDailyLiters)} لتر/يوم', key: const Key('supplier-max')),
          Text('درجة الموثوقية: $score', key: const Key('supplier-reliability')),
          Text('مسؤول الاتصال: ${supplier.contactName}', key: const Key('supplier-contact')),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('supplier-edit'),
            onPressed: () => _edit(context, supplier),
            child: const Text('تحديث بيانات المورد'),
          ),
        ],
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});

  final List<SupplyWeekDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }
    var peak = 1.0;
    for (final day in days) {
      final value = double.tryParse(day.liters) ?? 0;
      if (value > peak) {
        peak = value;
      }
    }
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_compact(day.liters), style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    Container(
                      height: 8 + ((double.tryParse(day.liters) ?? 0) / peak) * 70,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(day.label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<SupplierRecord?> _addSupplier(BuildContext context) async {
  final cubit = context.read<SupplyCubit>();
  final name = TextEditingController();
  final headquarters = TextEditingController();
  final contact = TextEditingController();
  final phone = TextEditingController();
  final daily = TextEditingController(text: '50000');
  SupplierRecord? created;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('إضافة شركة توريد جديدة'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الشركة')),
                const SizedBox(height: 16),
                TextField(controller: headquarters, decoration: const InputDecoration(labelText: 'المقر الرئيسي')),
                const SizedBox(height: 16),
                TextField(controller: contact, decoration: const InputDecoration(labelText: 'مسؤول الاتصال')),
                const SizedBox(height: 16),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                const SizedBox(height: 16),
                TextField(controller: daily, decoration: const InputDecoration(labelText: 'السعة اليومية (لتر)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final row = await cubit.createSupplier(
                name: name.text,
                headquarters: headquarters.text,
                contactName: contact.text,
                phone: phone.text,
                maxDailyLiters: daily.text,
              );
              if (row != null && dialogContext.mounted) {
                created = row;
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('حفظ المورد'),
          ),
        ],
      );
    },
  );
  name.dispose();
  headquarters.dispose();
  contact.dispose();
  phone.dispose();
  daily.dispose();
  return created;
}

Future<void> _create(BuildContext context, SupplyState state) async {
  final cubit = context.read<SupplyCubit>();
  String? supplierId = state.suppliers.isEmpty ? null : state.suppliers.first.id;
  String? productId = state.products.isEmpty ? null : state.products.first.id;
  String? tankId;
  final liters = TextEditingController();
  final notes = TextEditingController();
  final today = DateTime.now();
  final expected = TextEditingController(
    text: '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
  );
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          final tanks = state.tanks.where((item) => item.productId == productId).toList();
          if (tankId != null && tanks.every((item) => item.id != tankId)) {
            tankId = null;
          }
          tankId ??= tanks.isEmpty ? null : tanks.first.id;
          return AlertDialog(
            title: const Text('إنشاء طلب توريد جديد'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: supplierId,
                      decoration: const InputDecoration(labelText: 'المورد'),
                      items: [
                        for (final item in state.suppliers)
                          DropdownMenuItem(value: item.id, child: Text(item.name)),
                      ],
                      onChanged: (value) => setLocal(() => supplierId = value),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('supply-product'),
                      value: productId,
                      decoration: const InputDecoration(labelText: 'نوع الوقود'),
                      items: [
                        for (final item in state.products)
                          DropdownMenuItem(value: item.id, child: Text(item.name)),
                      ],
                      onChanged: (value) => setLocal(() {
                        productId = value;
                        tankId = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (tanks.isEmpty)
                      const Text('لا يوجد خزان لهذا النوع من الوقود.', style: TextStyle(color: AppColors.error))
                    else
                      DropdownButtonFormField<String>(
                        key: const Key('supply-tank'),
                        value: tankId,
                        decoration: const InputDecoration(labelText: 'الخزان'),
                        items: [
                          for (final item in tanks) DropdownMenuItem(value: item.id, child: Text(item.name)),
                        ],
                        onChanged: (value) => setLocal(() => tankId = value),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('supply-liters'),
                      controller: liters,
                      decoration: const InputDecoration(labelText: 'الكمية المطلوبة (لتر)'),
                    ),
                    const SizedBox(height: 16),
                    TextField(controller: expected, decoration: const InputDecoration(labelText: 'تاريخ التسليم المتوقع')),
                    const SizedBox(height: 16),
                    TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات إضافية')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                key: const Key('supply-save'),
                onPressed: supplierId == null || tankId == null || productId == null
                    ? null
                    : () async {
                        final ok = await cubit.createOrder(
                          supplierId: supplierId!,
                          tankId: tankId!,
                          productId: productId!,
                          liters: liters.text,
                          expectedOn: expected.text,
                          notes: notes.text,
                        );
                        if (ok && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      },
                child: const Text('تأكيد وإرسال الطلب'),
              ),
            ],
          );
        },
      );
    },
  );
  liters.dispose();
  notes.dispose();
  expected.dispose();
}

Future<void> _edit(BuildContext context, SupplierRecord supplier) async {
  final cubit = context.read<SupplyCubit>();
  final headquarters = TextEditingController(text: supplier.headquarters);
  final contact = TextEditingController(text: supplier.contactName);
  final phone = TextEditingController(text: supplier.phone);
  final daily = TextEditingController(text: supplier.maxDailyLiters);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('تحديث بيانات المورد'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: headquarters, decoration: const InputDecoration(labelText: 'المقر الرئيسي')),
              TextField(controller: contact, decoration: const InputDecoration(labelText: 'مسؤول الاتصال')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'الهاتف')),
              TextField(controller: daily, decoration: const InputDecoration(labelText: 'سعة التوريد اليومية')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final ok = await cubit.updateSupplier(
                id: supplier.id,
                headquarters: headquarters.text,
                contactName: contact.text,
                phone: phone.text,
                maxDailyLiters: daily.text,
              );
              if (ok && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );
  headquarters.dispose();
  contact.dispose();
  phone.dispose();
  daily.dispose();
}

String _compact(String raw) {
  final body = raw.endsWith('.000') ? raw.substring(0, raw.length - 4) : raw;
  return groupThousands(body.isEmpty ? '0' : body);
}
