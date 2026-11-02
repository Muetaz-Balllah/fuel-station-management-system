import 'dart:typed_data';

import 'package:frontend/core/reporting/report_fonts.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildDashboardPdf({
  required String date,
  required String revenue,
  required String liters,
  required String inventoryLiters,
  required int staffOnDuty,
  required List<ShiftLogRow> sessions,
  List<DashboardWeekDay> week = const [],
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  doc.addPage(
    pw.MultiPage(
      pageTheme: const pw.PageTheme(
        margin: pw.EdgeInsets.all(40),
        textDirection: pw.TextDirection.rtl,
      ),
      build: (context) => [
        pw.Text('FuelOps Libya — تقرير يومي', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('التاريخ: $date', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.Divider(),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _metric('المبيعات', '$revenue د.ل'),
            _metric('اللترات المباعة', '$liters لتر'),
            _metric('المخزون', '$inventoryLiters لتر'),
            _metric('الموظفون النشطون', '$staffOnDuty'),
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Text('ملخص الورديات', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (sessions.isEmpty)
          pw.Text('لا توجد ورديات في هذا اليوم.')
        else
          pw.Table.fromTextArray(
            headers: ['الوردية', 'النافذة', 'اللترات', 'الإيراد', 'المطابقة', 'الحالة'],
            data: [
              for (final row in sessions)
                [
                  row.code,
                  row.window,
                  row.liters ?? '—',
                  row.revenue ?? '—',
                  row.varianceLabel ?? '—',
                  row.statusLabel,
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerRight,
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
        if (week.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text('مقارنة مبيعات الورديات الأسبوعية', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: const ['اليوم', 'الصباحية', 'المسائية'],
            data: [
              for (final day in week) [day.label, '${day.morning} د.ل', '${day.evening} د.ل'],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerRight,
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
        ],
        pw.SizedBox(height: 24),
        pw.Text(
          'تم إنشاء التقرير آلياً من نظام إدارة المحطة.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _metric(String label, String value) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ),
  );
}
