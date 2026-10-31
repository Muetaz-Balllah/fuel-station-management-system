import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';

class ShiftTemplateForm extends StatefulWidget {
  const ShiftTemplateForm({super.key, this.existing, required this.onSubmit});

  final ShiftTemplateItem? existing;
  final Future<void> Function(ShiftDraft draft) onSubmit;

  @override
  State<ShiftTemplateForm> createState() => _ShiftTemplateFormState();
}

class _ShiftTemplateFormState extends State<ShiftTemplateForm> {
  late final TextEditingController _name;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _grace;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.nameAr ?? '');
    _start = TextEditingController(text: existing?.startsAt ?? '08:00');
    _end = TextEditingController(text: existing?.endsAt ?? '16:00');
    _grace = TextEditingController(text: '${existing?.graceMinutes ?? 10}');
    _active = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _grace.dispose();
    super.dispose();
  }

  bool get _overnight {
    final start = _start.text.trim();
    final end = _end.text.trim();
    if (start.length < 4 || end.length < 4) {
      return false;
    }
    return end.compareTo(start) <= 0;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الوردية مطلوب.');
      return;
    }
    final grace = int.tryParse(_grace.text.trim());
    if (grace == null || grace < 0 || grace > 120) {
      setState(() => _error = 'مهلة التأخير يجب أن تكون بين 0 و 120 دقيقة.');
      return;
    }
    setState(() => _error = null);
    await widget.onSubmit(
      ShiftDraft(
        nameAr: name,
        startsAt: _start.text.trim(),
        endsAt: _end.text.trim(),
        graceMinutes: grace,
        isActive: _active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('shift-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم الوردية'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _start,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'وقت البداية'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _end,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'وقت النهاية'),
              ),
            ),
          ],
        ),
        if (_overnight)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'هذه الوردية تمتد إلى اليوم التالي.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _grace,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'مهلة التأخير بالدقائق'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('الوردية نشطة'),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              key: const Key('shift-error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        FilledButton(
          key: const Key('shift-save'),
          onPressed: _save,
          child: const Text('حفظ الوردية'),
        ),
      ],
    );
  }
}
