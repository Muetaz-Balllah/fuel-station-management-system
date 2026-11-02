import 'dart:typed_data';

import 'package:frontend/core/reporting/report_fonts.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildAttendancePdf({
  required List<AttendanceRow> rows,
  String? date,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  doc.addPage(
    pw.MultiPage(
      pageTheme: const pw.PageTheme(
        margin: pw.EdgeInsets.all(36),
        textDirection: pw.TextDirection.rtl,
      ),
      build: (context) => [
        pw.Text('تقرير الحضور وتكليف المضخات', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          date == null || date.isEmpty ? 'نظام إدارة المحطة' : 'تاريخ اليوم: $date',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
        ),
        pw.Divider(),
        pw.SizedBox(height: 8),
        if (rows.isEmpty)
          pw.Text('لا يوجد تكليف في هذا اليوم.')
        else
          pw.Table.fromTextArray(
            headers: const ['الموظف', 'الرقم', 'التكليف', 'الحضور', 'الانصراف', 'الحالة', 'ملاحظة'],
            data: [
              for (final row in rows)
                [
                  '${row.fullName}\n${row.jobTitle}',
                  row.employeeCode,
                  row.assignments.isEmpty
                      ? '—'
                      : row.assignments.map((item) => '${item.pumpCode} مسدس ${item.nozzleCode}').join('\n'),
                  row.checkInLabel ?? '—',
                  row.checkOutLabel ?? '—',
                  row.statusLabel,
                  row.note ?? '—',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerRight,
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'تم إنشاء التقرير آلياً من سجل الحضور والورديات.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc.save();
}
