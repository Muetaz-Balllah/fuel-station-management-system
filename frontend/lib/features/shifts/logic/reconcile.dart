class DutyPreview {
  const DutyPreview({
    required this.liters,
    required this.expectedCash,
    required this.variance,
    required this.kind,
  });

  final String liters;
  final String expectedCash;
  final String variance;
  final String kind;

  String get phrase {
    if (kind == 'match') {
      return 'مطابق';
    }
    if (kind == 'surplus') {
      return 'فائض +$variance';
    }
    final amount = variance.startsWith('-') ? variance.substring(1) : variance;
    return 'عجز −$amount';
  }
}

class PreviewLine {
  const PreviewLine({required this.opening, required this.closing, required this.unitPrice});

  final String opening;
  final String closing;
  final String unitPrice;
}

/// First validation failure for close submission, with a field-specific Arabic message.
String? validateCloseFields({
  required List<PreviewLine> lines,
  required List<String> lineLabels,
  required String cash,
}) {
  if (lines.length != lineLabels.length) {
    throw ArgumentError('lineLabels must match lines length.');
  }
  if (lines.isEmpty) {
    return 'لا توجد مسدسات في الوردية.';
  }
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final label = lineLabels[index];
    final closingRaw = line.closing.trim();
    if (closingRaw.isEmpty) {
      return 'أدخل قراءة الإغلاق الختامية لـ $label.';
    }
    final closing = _scaled(closingRaw, 3);
    if (closing == null) {
      return 'قراءة الإغلاق لـ $label غير صالحة. استخدم أرقاماً فقط (مثل 1234567.000).';
    }
    if (closing < 0) {
      return 'قراءة الإغلاق لـ $label لا يمكن أن تكون سالبة.';
    }
    final opening = _scaled(line.opening, 3);
    if (opening == null) {
      return 'قراءة الافتتاح لـ $label غير متاحة. تواصل مع المشرف.';
    }
    if (closing < opening) {
      return 'قراءة الإغلاق لـ $label أقل من قراءة الافتتاح (${line.opening}).';
    }
    final price = _scaled(line.unitPrice, 3);
    if (price == null) {
      return 'تسعيرة الوقود لـ $label غير متاحة. تواصل مع المشرف.';
    }
  }
  final cashRaw = cash.trim();
  if (cashRaw.isEmpty) {
    return 'أدخل المبلغ النقدي المسلّم في الصندوق (د.ل).';
  }
  final handed = _scaled(cashRaw, 2);
  if (handed == null) {
    return 'المبلغ النقدي غير صالح. استخدم أرقاماً فقط (مثل 642.00).';
  }
  if (handed < 0) {
    return 'المبلغ النقدي لا يمكن أن يكون سالباً.';
  }
  return null;
}

/// Same half-up scales as the server: liters 3 dp, money 2 dp. No binary floats.
DutyPreview? previewDuty({required List<PreviewLine> lines, required String cash}) {
  if (lines.isEmpty) {
    return null;
  }
  var litersMilli = 0;
  var expectedCents = 0;
  for (final line in lines) {
    final opening = _scaled(line.opening, 3);
    final closing = _scaled(line.closing, 3);
    final price = _scaled(line.unitPrice, 3);
    if (opening == null || closing == null || price == null || closing < opening) {
      return null;
    }
    final liters = closing - opening;
    litersMilli += liters;
    expectedCents += _roundDiv(liters * price, 10000);
  }
  final handed = _scaled(cash, 2);
  if (handed == null) {
    return null;
  }
  final variance = handed - expectedCents;
  final kind = variance == 0
      ? 'match'
      : variance > 0
          ? 'surplus'
          : 'shortage';
  return DutyPreview(
    liters: _format(litersMilli, 3),
    expectedCash: _format(expectedCents, 2),
    variance: _format(variance, 2),
    kind: kind,
  );
}

String groupThousands(String number) {
  final negative = number.startsWith('-');
  final body = negative ? number.substring(1) : number;
  final parts = body.split('.');
  final whole = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');
  final fraction = parts.length > 1 ? '.${parts[1]}' : '';
  return '${negative ? '-' : ''}$whole$fraction';
}

int? _scaled(String raw, int scale) {
  final trimmed = _normalizeWesternDigits(raw.trim().replaceAll(',', ''));
  if (trimmed.isEmpty) {
    return null;
  }
  var negative = false;
  var body = trimmed;
  if (body.startsWith('-')) {
    negative = true;
    body = body.substring(1);
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(body)) {
    return null;
  }
  final parts = body.split('.');
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length <= scale) {
    final digits = parts[0] + fraction.padRight(scale, '0');
    final value = int.parse(digits);
    return negative ? -value : value;
  }
  var base = int.parse(parts[0] + fraction.substring(0, scale));
  if (int.parse(fraction[scale]) >= 5) {
    base += 1;
  }
  return negative ? -base : base;
}

int _roundDiv(int value, int divisor) {
  final negative = value < 0;
  final magnitude = value.abs();
  var whole = magnitude ~/ divisor;
  final rest = magnitude % divisor;
  if (rest * 2 >= divisor) {
    whole += 1;
  }
  return negative ? -whole : whole;
}

String _normalizeWesternDigits(String raw) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var out = raw;
  for (var digit = 0; digit < 10; digit++) {
    out = out.replaceAll(eastern[digit], '$digit');
    out = out.replaceAll(persian[digit], '$digit');
  }
  return out;
}

String _format(int value, int scale) {
  final negative = value < 0;
  final digits = value.abs().toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  return '${negative ? '-' : ''}${digits.substring(0, split)}.${digits.substring(split)}';
}
