import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';

class LicenseRenewalBanner extends StatelessWidget {
  const LicenseRenewalBanner({super.key, required this.expiresOn, this.today});

  final String expiresOn;
  final DateTime? today;

  static bool due(String expiresOn, [DateTime? today]) {
    final expiry = DateTime.tryParse(expiresOn);
    if (expiry == null) {
      return false;
    }
    final now = today ?? DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(expiry.year, expiry.month, expiry.day);
    return end.difference(start).inDays <= 30;
  }

  @override
  Widget build(BuildContext context) {
    if (!due(expiresOn, today)) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('license-warning'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error),
      ),
      child: Text(
        'الترخيص ينتهي في $expiresOn. جدّده خلال 30 يوماً.',
        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
      ),
    );
  }
}
