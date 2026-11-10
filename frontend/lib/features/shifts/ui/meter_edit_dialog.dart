import 'package:flutter/material.dart';
import 'package:frontend/core/widgets/dispose_controllers.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';

class MeterEditRequest {
  const MeterEditRequest({required this.reason, required this.lines});

  final String reason;
  final List<Map<String, String>> lines;
}

Future<MeterEditRequest?> showMeterEditDialog(
  BuildContext context, {
  required List<DutyLine> lines,
  List<MeterAdjustment> adjustments = const [],
}) {
  final controllers = {for (final line in lines) line.nozzleId: TextEditingController(text: line.openingMeter)};
  final reason = TextEditingController();
  return showDialog<MeterEditRequest>(
    context: context,
    builder: (dialogContext) {
      return DisposeControllers(
        controllers: [...controllers.values, reason],
        child: AlertDialog(
          title: const Text('تعديل عداد المسدس'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'يظهر التعديل في سجل الوردية وعند اعتماد المدير. اكتب القراءة الجديدة وسببها.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  for (final line in lines) ...[
                    TextField(
                      controller: controllers[line.nozzleId],
                      decoration: InputDecoration(
                        labelText: 'مسدس ${line.nozzleCode} • ${line.productName}',
                        helperText: () {
                          final prior = adjustments.where((item) => item.nozzleId == line.nozzleId).toList();
                          if (prior.isEmpty) {
                            return 'القراءة الحالية ${line.openingMeter}';
                          }
                          return 'القراءة السابقة ${prior.first.previousMeter}';
                        }(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'سبب التعديل'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final note = reason.text.trim();
                if (note.isEmpty) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  MeterEditRequest(
                    reason: note,
                    lines: [
                      for (final line in lines)
                        {'nozzle_id': line.nozzleId, 'opening_meter': controllers[line.nozzleId]!.text.trim()},
                    ],
                  ),
                );
              },
              child: const Text('حفظ التعديل'),
            ),
          ],
        ),
      );
    },
  );
}
