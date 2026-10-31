import 'package:flutter/material.dart';
import 'package:frontend/core/theming/app_colors.dart';

class LoginBrandPanel extends StatelessWidget {
  const LoginBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.primary,
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.local_gas_station, color: Color(0xFFB7C6F2), size: 40),
            SizedBox(height: 16),
            Text(
              'نظام إدارة الوقود',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'الحل المتكامل لإدارة العمليات اليومية ومراقبة المخزون والمبيعات بدقة عالية وموثوقية تامة.',
              style: TextStyle(color: Color(0xFFB7C6F2), fontSize: 18, height: 1.5),
            ),
            Spacer(),
            _BrandPoint(
              icon: Icons.health_and_safety_outlined,
              title: 'أمان وموثوقية',
              subtitle: 'تشفير كامل للبيانات وحماية الحسابات',
            ),
            SizedBox(height: 20),
            _BrandPoint(
              icon: Icons.insights_outlined,
              title: 'تقارير فورية',
              subtitle: 'مراقبة حية للمخزون وحركة المبيعات',
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandPoint extends StatelessWidget {
  const _BrandPoint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: const Color(0xFF8392BC)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF8392BC), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
