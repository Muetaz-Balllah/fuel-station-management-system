import 'package:flutter/foundation.dart';

class ShiftAssignment {
  const ShiftAssignment({
    required this.templateId,
    required this.shiftName,
    required this.window,
    required this.employeeNames,
  });

  final String templateId;
  final String shiftName;
  final String window;
  final List<String> employeeNames;
}

class ShiftRoster {
  static final updates = ChangeNotifier();
  static final Map<String, ShiftAssignment> _saved = {};

  static List<ShiftAssignment> get saved => _saved.values.toList();

  static Iterable<String> get templateIds => _saved.keys;

  static void pruneExcept(Iterable<String> keepIds) {
    final keep = keepIds.toSet();
    final stale = _saved.keys.where((id) => !keep.contains(id)).toList();
    if (stale.isEmpty) {
      return;
    }
    for (final id in stale) {
      _saved.remove(id);
    }
    updates.notifyListeners();
  }

  static ShiftAssignment? of(String templateId) => _saved[templateId];

  static void save(ShiftAssignment assignment) {
    _saved[assignment.templateId] = assignment;
    updates.notifyListeners();
  }

  static void remove(String templateId) {
    if (_saved.remove(templateId) != null) {
      updates.notifyListeners();
    }
  }

  static List<ShiftAssignment> timetable() {
    if (_saved.isNotEmpty) {
      return saved;
    }
    return const [
      ShiftAssignment(
        templateId: 'preview-morning',
        shiftName: 'الوردية الصباحية',
        window: '08:00 – 16:00',
        employeeNames: ['محمد مصطفى القذافي'],
      ),
      ShiftAssignment(
        templateId: 'preview-evening',
        shiftName: 'الوردية المسائية',
        window: '16:00 – 00:00',
        employeeNames: ['سالم الشريف'],
      ),
    ];
  }
}
