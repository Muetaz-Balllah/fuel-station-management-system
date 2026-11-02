import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';

void main() {
  test('4280 liters at 0.150 matches 642.00 and the five-dinar cases', () {
    const lines = [
      PreviewLine(opening: '1841200.000', closing: '1843450.000', unitPrice: '0.150'),
      PreviewLine(opening: '1621075.000', closing: '1623105.000', unitPrice: '0.150'),
    ];
    final matched = previewDuty(lines: lines, cash: '642.00');
    expect(matched, isNotNull);
    expect(matched!.liters, '4280.000');
    expect(matched.expectedCash, '642.00');
    expect(matched.variance, '0.00');
    expect(matched.kind, 'match');
    expect(matched.phrase, 'مطابق');

    final shortage = previewDuty(lines: lines, cash: '637.00')!;
    expect(shortage.variance, '-5.00');
    expect(shortage.kind, 'shortage');
    expect(shortage.phrase, 'عجز −5.00');

    final surplus = previewDuty(lines: lines, cash: '647.00')!;
    expect(surplus.variance, '5.00');
    expect(surplus.kind, 'surplus');
    expect(surplus.phrase, 'فائض +5.00');

    final second = previewDuty(
      lines: const [PreviewLine(opening: '0', closing: '8120', unitPrice: '0.150')],
      cash: '1223.00',
    )!;
    expect(second.expectedCash, '1218.00');
    expect(second.variance, '5.00');
  });

  test('validateCloseFields reports the first invalid field', () {
    const lines = [
      PreviewLine(opening: '100.000', closing: '50.000', unitPrice: '0.150'),
      PreviewLine(opening: '200.000', closing: '300.000', unitPrice: '0.150'),
    ];
    expect(
      validateCloseFields(lines: lines, lineLabels: const ['PUMP-01 (بنزين)', 'PUMP-02 (بنزين)'], cash: '15.00'),
      contains('PUMP-01'),
    );
    expect(
      validateCloseFields(
        lines: const [PreviewLine(opening: '100.000', closing: '200.000', unitPrice: '0.150')],
        lineLabels: const ['PUMP-01 (بنزين)'],
        cash: '',
      ),
      contains('المبلغ النقدي'),
    );
    expect(
      validateCloseFields(
        lines: const [PreviewLine(opening: '100.000', closing: 'abc', unitPrice: '0.150')],
        lineLabels: const ['PUMP-01 (بنزين)'],
        cash: '10.00',
      ),
      contains('غير صالحة'),
    );
    expect(
      validateCloseFields(
        lines: const [PreviewLine(opening: '100.000', closing: '200.000', unitPrice: '0.150')],
        lineLabels: const ['PUMP-01 (بنزين)'],
        cash: '15.00',
      ),
      isNull,
    );
  });

  test('accepts eastern arabic numerals in cash and meters', () {
    final preview = previewDuty(
      lines: const [PreviewLine(opening: '١٠٠.٠٠٠', closing: '٢٠٠.٠٠٠', unitPrice: '0.150')],
      cash: '١٥.٠٠',
    );
    expect(preview, isNotNull);
    expect(preview!.expectedCash, '15.00');
    expect(preview.kind, 'match');
  });

  test('mixed prices stay on their own lines', () {
    final preview = previewDuty(
      lines: const [
        PreviewLine(opening: '0', closing: '1000', unitPrice: '0.150'),
        PreviewLine(opening: '0', closing: '1000', unitPrice: '0.180'),
      ],
      cash: '330.00',
    )!;
    expect(preview.expectedCash, '330.00');
    expect(preview.kind, 'match');
  });
}