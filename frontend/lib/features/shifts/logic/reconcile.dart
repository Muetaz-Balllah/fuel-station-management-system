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
  final trimmed = raw.trim().replaceAll(',', '');
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

String _format(int value, int scale) {
  final negative = value < 0;
  final digits = value.abs().toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  return '${negative ? '-' : ''}${digits.substring(0, split)}.${digits.substring(split)}';
}
