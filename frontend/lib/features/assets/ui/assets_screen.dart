import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/layout/responsive_layout.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/assets/data/models/asset_models.dart';
import 'package:frontend/features/assets/data/repos/assets_repository.dart';
import 'package:frontend/features/assets/logic/cubit/assets_cubit.dart';
import 'package:frontend/features/assets/ui/widgets/tank_form.dart';

const _green = Color(0xFF15803D);
const _orange = Color(0xFFC2410C);

class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, this.cubit});

  final AssetsCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final view = const _RefreshingAssets();
    if (cubit != null) {
      return BlocProvider.value(value: cubit!, child: view);
    }
    return BlocProvider(
      create: (_) => AssetsCubit(getIt<AssetsRepository>())..load(),
      child: view,
    );
  }
}

class _RefreshingAssets extends StatefulWidget {
  const _RefreshingAssets();

  @override
  State<_RefreshingAssets> createState() => _RefreshingAssetsState();
}

class _RefreshingAssetsState extends State<_RefreshingAssets> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        context.read<AssetsCubit>().load();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const AssetsView();
}

class AssetsView extends StatelessWidget {
  const AssetsView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AssetsCubit>().state;
    final board = state.board;
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: () => context.read<AssetsCubit>().load(),
        child: ListView(
          padding: managerPagePadding(context),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const subtitle = Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'مراقبة حية لمستويات الوقود — خزان مستقل 1:1 لكل مضخة',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: board == null ? null : () => _addPump(context, board),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة مضخة'),
                    ),
                    FilledButton.icon(
                      onPressed: board == null ? null : () => _addTank(context, board),
                      icon: const Icon(Icons.storage),
                      label: const Text('إضافة خزان جديد'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 640) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [subtitle, const SizedBox(height: 12), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(child: subtitle),
                    const SizedBox(width: 12),
                    actions,
                  ],
                );
              },
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(state.error!, key: const Key('assets-error'), style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: 16),
            if (board == null)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (board.cards.isEmpty && board.freeTanks.isEmpty)
                const Text('لا توجد مضخات بعد. أضف خزاناً ثم اربطه بمضخة.')
              else if (board.cards.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 860 ? 2 : 1;
                    final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final card in board.cards)
                          SizedBox(width: width, child: _PumpCard(card: card)),
                      ],
                    );
                  },
                ),
              if (board.freeTanks.isNotEmpty) ...[
                const SizedBox(height: 20),
                _FreeTanksPanel(tanks: board.freeTanks),
              ],
            ],
            const SizedBox(height: 28),
            _EventLog(state: state),
          ],
        ),
      ),
    );
  }
}

class _FreeTanksPanel extends StatelessWidget {
  const _FreeTanksPanel({required this.tanks});

  final List<AssetTank> tanks;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'خزانات غير مرتبطة بمضخة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          const Text(
            'بعد حذف المضخة ينتقل الخزان إلى هذه القائمة. احذف الخزان من هنا أو اربطه بمضخة جديدة عبر «إضافة مضخة».',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final tank in tanks) _FreeTankRow(tank: tank),
        ],
      ),
    );
  }
}

class _FreeTankRow extends StatelessWidget {
  const _FreeTankRow({required this.tank});

  final AssetTank tank;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tank.code} • ${tank.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${tank.productName} • ${tank.percent}% • L ${formatQty(tank.currentLiters)} / ${formatQty(tank.capacityLiters)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => _adjust(context, tank), child: const Text('تسوية')),
          TextButton(
            onPressed: () => _confirmDelete(
              context,
              'حذف الخزان ${tank.code} نهائياً؟',
              () => context.read<AssetsCubit>().deleteTank(tank.id),
            ),
            child: const Text('حذف الخزان', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _PumpCard extends StatelessWidget {
  const _PumpCard({required this.card});

  final PumpCardData card;

  @override
  Widget build(BuildContext context) {
    final maintenance = card.pump.status == 'maintenance';
    final alert = maintenance || card.tank.cardBandLabel != 'مستقر';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.local_gas_station, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'وحدة مضخة ${card.pump.code} (${card.tank.productName})',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Pill(card.pump.statusLabel, maintenance ? _orange : _green),
                        _Pill('خزان مستقل مخصص: ${card.tank.code}', AppColors.primary),
                        _Pill(card.tank.cardBandLabel, alert ? _orange : _green),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _CapacityBlock(percent: card.tank.percent, code: card.tank.code, alert: alert),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Stat('سعة الخزان المستقل', 'L ${formatQty(card.tank.capacityLiters)}'),
                    _Stat('الكمية المتوفرة', 'L ${formatQty(card.tank.currentLiters)}', alert: alert),
                    _Stat('آخر توريد للخزان', card.tank.lastReceiptLabel ?? '—'),
                    _Stat('معدل السحب اليومي', 'L ${formatQty(card.tank.todayLiters)}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('مسدسات التعبئة بالمضخة', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(card.pump.code, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          for (final nozzle in card.nozzles) _NozzleRow(nozzle: nozzle, pumpId: card.pump.id),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _addNozzle(context, card),
                icon: const Icon(Icons.add),
                label: const Text('إضافة مسدس'),
              ),
              TextButton(
                onPressed: () => context.read<AssetsCubit>().setPumpStatus(
                      pumpId: card.pump.id,
                      status: maintenance ? 'active' : 'maintenance',
                    ),
                child: Text(maintenance ? 'إعادة التشغيل' : 'وضع الصيانة'),
              ),
              TextButton(
                onPressed: () => _confirmDelete(
                  context,
                  'حذف المضخة ${card.pump.code}؟\n'
                  'سيظهر الخزان ${card.tank.code} في قائمة «خزانات غير مرتبطة» بالأسفل ويمكن حذفه من هناك.',
                  () => context.read<AssetsCubit>().deletePump(card.pump.id),
                ),
                child: const Text('حذف المضخة', style: TextStyle(color: AppColors.error)),
              ),
              TextButton(
                onPressed: () => _adjust(context, card.tank),
                child: const Text('تسوية'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapacityBlock extends StatelessWidget {
  const _CapacityBlock({required this.percent, required this.code, required this.alert});

  final int percent;
  final String code;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final fill = (percent.clamp(0, 100)) / 100;
    final ink = alert ? _orange : AppColors.primary;
    return Container(
      width: 92,
      height: 108,
      decoration: BoxDecoration(
        color: const Color(0xFFE7EEFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: fill == 0 ? 0 : fill,
              widthFactor: 1,
              child: ColoredBox(color: ink),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percent%',
                  style: TextStyle(color: fill > 0.55 ? Colors.white : AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20),
                ),
                Text(code, style: TextStyle(fontSize: 10, color: fill > 0.55 ? const Color(0xFFE7EEFF) : AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NozzleRow extends StatelessWidget {
  const _NozzleRow({required this.nozzle, required this.pumpId});

  final AssetNozzle nozzle;
  final String pumpId;

  @override
  Widget build(BuildContext context) {
    final ready = nozzle.status == 'ready';
    final color = ready ? _green : _orange;
    final cubit = context.read<AssetsCubit>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${nozzle.code} (${nozzle.label})', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                Text('${nozzle.statusLabel} • عداد ${formatQty(nozzle.currentMeter)} L', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => cubit.setNozzleStatus(
              nozzleId: nozzle.id,
              status: ready ? 'valve_check' : 'ready',
            ),
            child: Text(ready ? 'تعطيل مؤقت' : 'تفعيل'),
          ),
          TextButton(
            onPressed: () => _confirmDelete(context, 'حذف المسدس ${nozzle.code}؟', () => cubit.deleteNozzle(nozzle.id)),
            child: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDelete(BuildContext context, String message, Future<bool> Function() action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تأكيد'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('نعم')),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    return;
  }
  final cubit = context.read<AssetsCubit>();
  final success = await action();
  if (!context.mounted) {
    return;
  }
  if (!success && cubit.state.error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cubit.state.error!)));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: alert ? _orange : AppColors.onSurface)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.state});

  final AssetsState state;

  @override
  Widget build(BuildContext context) {
    final products = state.board?.products ?? const <AssetProduct>[];
    final page = state.eventOffset ~/ AssetsState.pageSize + 1;
    final pages = math.max(1, (state.eventTotal / AssetsState.pageSize).ceil());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('سجل القراءات التفصيلي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            DropdownButton<String>(
              value: state.productFilter,
              items: [
                const DropdownMenuItem(value: '', child: Text('جميع أنواع الوقود')),
                for (final product in products)
                  DropdownMenuItem(value: product.id, child: Text(product.nameAr)),
              ],
              onChanged: (value) {
                if (value != null) {
                  context.read<AssetsCubit>().filterEvents(value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                color: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: const Row(
                  children: [
                    Expanded(child: Text('التوقيت', style: TextStyle(color: Colors.white))),
                    Expanded(flex: 2, child: Text('المسار', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('نوع الحدث', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('الكمية', style: TextStyle(color: Colors.white))),
                    Expanded(child: Text('المسؤول', style: TextStyle(color: Colors.white))),
                  ],
                ),
              ),
              if (state.events.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حركات بعد.'))
              else
                for (final event in state.events)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(event.createdAt, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Text(event.path)),
                        Expanded(child: Text(event.movementLabel)),
                        Expanded(child: Text('${formatQty(event.litersDelta)} L')),
                        Expanded(child: Text(event.actorName)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('صفحة $page من $pages'),
            const Spacer(),
            TextButton(
              onPressed: state.eventOffset == 0
                  ? null
                  : () => context.read<AssetsCubit>().changePage(state.eventOffset - AssetsState.pageSize),
              child: const Text('السابق'),
            ),
            TextButton(
              onPressed: state.eventOffset + AssetsState.pageSize >= state.eventTotal
                  ? null
                  : () => context.read<AssetsCubit>().changePage(state.eventOffset + AssetsState.pageSize),
              child: const Text('التالي'),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _addTank(BuildContext context, AssetBoard board) async {
  final cubit = context.read<AssetsCubit>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('إضافة خزان جديد للنظام'),
        content: SizedBox(
          width: 420,
          child: TankForm(
            products: board.products,
            onSubmit: (name, productId, capacity) async {
              final ok = await cubit.createTank(name: name, productId: productId, capacity: capacity);
              if (ok && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              } else if (dialogContext.mounted && cubit.state.error != null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(cubit.state.error!)));
              }
            },
          ),
        ),
      );
    },
  );
}

Future<void> _addPump(BuildContext context, AssetBoard board) async {
  final cubit = context.read<AssetsCubit>();
  final code = TextEditingController();
  String? tankId = board.freeTanks.isEmpty ? null : board.freeTanks.first.id;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('إضافة مضخة'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز المضخة')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: tankId,
                    decoration: const InputDecoration(labelText: 'الخزان المستقل'),
                    items: [
                      for (final tank in board.freeTanks)
                        DropdownMenuItem(value: tank.id, child: Text('${tank.code} • ${tank.name}')),
                    ],
                    onChanged: board.freeTanks.isEmpty ? null : (value) => setLocal(() => tankId = value),
                  ),
                  if (board.freeTanks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('كل الخزانات مرتبطة بمضخة. أضف خزاناً جديداً أولاً.'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                onPressed: tankId == null
                    ? null
                    : () async {
                        final ok = await cubit.createPump(code: code.text, tankId: tankId!);
                        if (!dialogContext.mounted) {
                          return;
                        }
                        if (ok) {
                          Navigator.pop(dialogContext);
                        } else if (cubit.state.error != null) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(cubit.state.error!)),
                          );
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
  code.dispose();
}

Future<void> _addNozzle(BuildContext context, PumpCardData card) async {
  final cubit = context.read<AssetsCubit>();
  final code = TextEditingController();
  final label = TextEditingController(text: 'يمين');
  final meter = TextEditingController(text: '0');
  var status = 'ready';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('إضافة مسدس تعبئة جديد'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('المضخة\n${card.pump.code}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Expanded(child: Text('الخزان\n${card.tank.code} • ${card.tank.productName}')),
                    ],
                  ),
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'رمز المسدس')),
                  TextField(controller: label, decoration: const InputDecoration(labelText: 'الجهة')),
                  TextField(controller: meter, decoration: const InputDecoration(labelText: 'العداد الابتدائي')),
                  DropdownButton<String>(
                    value: status,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'ready', child: Text('جاهز')),
                      DropdownMenuItem(value: 'valve_check', child: Text('فحص الصمام')),
                      DropdownMenuItem(value: 'calibrating', child: Text('معايرة عداد')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setLocal(() => status = value);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () async {
                  final ok = await cubit.createNozzle(
                    pumpId: card.pump.id,
                    code: code.text,
                    label: label.text,
                    meter: meter.text,
                    status: status,
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
    },
  );
  code.dispose();
  label.dispose();
  meter.dispose();
}

Future<void> _adjust(BuildContext context, AssetTank tank) async {
  final cubit = context.read<AssetsCubit>();
  final delta = TextEditingController();
  final note = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('تسوية ${tank.code}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: delta, decoration: const InputDecoration(labelText: 'الكمية (+ أو -)')),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'السبب')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final ok = await cubit.adjust(tankId: tank.id, delta: delta.text, note: note.text);
              if (!dialogContext.mounted) {
                return;
              }
              if (ok) {
                Navigator.pop(dialogContext);
              } else if (cubit.state.error != null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(cubit.state.error!)));
              }
            },
            child: const Text('تسجيل'),
          ),
        ],
      );
    },
  );
  delta.dispose();
  note.dispose();
}
