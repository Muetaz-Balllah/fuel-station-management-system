import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';
import 'package:frontend/features/supply/data/models/supply_models.dart';
import 'package:frontend/features/supply/data/repos/supply_repository.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.openCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOnce());
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
          const Text(
            'إدارة التوريدات والموردين',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
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
            child: FilledButton.icon(
              key: const Key('supply-create'),
              onPressed: state.loaded ? () => _create(context, state) : null,
              icon: const Icon(Icons.add),
              label: const Text('إنشاء طلب توريد جديد'),
            ),
          ),
          const SizedBox(height: 12),
          const Text('سجل طلبات التوريد الأخيرة', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (state.orders.isEmpty)
            const Text('لا توجد طلبات توريد.')
          else
            for (final order in state.orders) _OrderRow(order: order),
          const SizedBox(height: 20),
          if (supplier != null) _SupplierCard(supplier: supplier),
          const SizedBox(height: 12),
          TextButton(
            onPressed: state.suppliers.isEmpty
                ? null
                : () {
                    final index = state.suppliers.indexWhere((item) => item.id == state.selectedSupplierId);
                    final next = state.suppliers[(index + 1) % state.suppliers.length];
                    context.read<SupplyCubit>().selectSupplier(next.id);
                  },
            child: const Text('عرض الكل'),
          ),
          const Text('نشاط التوريد الأسبوعي', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _WeekBars(days: state.week),
        ],
      ),
    );
  }
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
  const _SupplierCard({required this.supplier});

  final SupplierRecord supplier;

  @override
  Widget build(BuildContext context) {
    final score = supplier.reliability == null ? '—' : '${supplier.reliability}%';
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تفاصيل المورد الرئيسي', style: TextStyle(fontWeight: FontWeight.w700)),
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
                    TextField(
                      key: const Key('supply-liters'),
                      controller: liters,
                      decoration: const InputDecoration(labelText: 'الكمية المطلوبة (لتر)'),
                    ),
                    TextField(controller: expected, decoration: const InputDecoration(labelText: 'تاريخ التسليم المتوقع')),
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
