import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/logic/duty_format.dart';

void main() {
  test('prefers server work hours label', () {
    const duty = DutyRecord(
      id: 'd',
      sessionId: 's',
      fullName: 'x',
      employeeCode: 'e',
      status: 'approved',
      statusLabel: 'معتمدة',
      openedAt: '2026-11-02T06:12:34.567Z',
      workHoursLabel: '08:12 – 16:05 · 7س 53د',
      liters: null,
      expectedCash: null,
      cashHanded: null,
      variance: null,
      varianceKind: null,
      varianceLabel: null,
      approvedByName: null,
      rejectReason: null,
      businessDate: '2026-11-02',
      lines: [],
    );
    expect(dutyWorkHoursLabel(duty), '08:12 – 16:05 · 7س 53د');
  });

  test('formats from iso without fractional noise', () {
    const duty = DutyRecord(
      id: 'd',
      sessionId: 's',
      fullName: 'x',
      employeeCode: 'e',
      status: 'approved',
      statusLabel: 'معتمدة',
      openedAt: '2026-11-02T06:00:00.000Z',
      submittedAt: '2026-11-02T14:30:00.000Z',
      liters: null,
      expectedCash: null,
      cashHanded: null,
      variance: null,
      varianceKind: null,
      varianceLabel: null,
      approvedByName: null,
      rejectReason: null,
      businessDate: '2026-11-02',
      lines: [],
    );
    final label = dutyWorkHoursLabel(duty);
    expect(label, isNot(contains('.')));
    expect(label, isNot(contains('T')));
    expect(label, contains('–'));
  });
}
