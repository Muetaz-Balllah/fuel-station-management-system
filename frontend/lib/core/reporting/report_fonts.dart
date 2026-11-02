import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.ThemeData> arabicPdfTheme() async {
  final data = await rootBundle.load('assets/fonts/NotoNaskhArabic.ttf');
  final font = pw.Font.ttf(data);
  return pw.ThemeData.withFont(base: font, bold: font);
}
