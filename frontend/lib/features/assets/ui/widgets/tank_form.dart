import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/assets/data/models/asset_models.dart';

class TankForm extends StatefulWidget {
  const TankForm({super.key, required this.products, required this.onSubmit});

  final List<AssetProduct> products;
  final Future<void> Function(String name, String productId, String capacity) onSubmit;

  @override
  State<TankForm> createState() => _TankFormState();
}

class _TankFormState extends State<TankForm> {
  final _name = TextEditingController();
  final _capacity = TextEditingController();
  String? _productId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.products.isNotEmpty) {
      _productId = widget.products.first.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'اسم الخزان مطلوب.');
      return;
    }
    final productId = _productId;
    if (productId == null) {
      setState(() => _error = 'اختر نوع الوقود.');
      return;
    }
    if (_capacity.text.trim().isEmpty) {
      setState(() => _error = 'سعة الخزان مطلوبة.');
      return;
    }
    setState(() => _error = null);
    await widget.onSubmit(_name.text.trim(), productId, _capacity.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('tank-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم الخزان'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _productId,
          decoration: const InputDecoration(labelText: 'نوع الوقود'),
          items: [
            for (final product in widget.products)
              DropdownMenuItem(value: product.id, child: Text(product.nameAr)),
          ],
          onChanged: (value) => setState(() => _productId = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _capacity,
          decoration: const InputDecoration(labelText: 'السعة باللتر'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const Key('tank-error'), style: const TextStyle(color: AppColors.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('tank-save'),
          onPressed: _save,
          child: const Text('حفظ الخزان'),
        ),
      ],
    );
  }
}
