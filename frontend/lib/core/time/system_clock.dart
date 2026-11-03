import 'package:dio/dio.dart';

/// Server-authoritative clock; business dates must not follow the device clock.
class SystemClock {
  SystemClock._();

  static Duration _skew = Duration.zero;
  static String? _businessDate;
  static String? _timezone;
  static String? _localTime;

  static String? get businessDate => _businessDate;
  static String? get timezone => _timezone;
  static String? get localTime => _localTime;

  static DateTime nowUtc() => DateTime.now().toUtc().add(_skew);

  static String todayIso() {
    if (_businessDate != null && _businessDate!.isNotEmpty) {
      return _businessDate!;
    }
    return _formatDate(nowUtc());
  }

  static Future<void> sync(Dio dio) async {
    final response = await dio.get('/api/v1/system/clock');
    final body = response.data as Map<String, dynamic>;
    final utcRaw = body['utc'] as String?;
    if (utcRaw != null) {
      final serverUtc = DateTime.parse(utcRaw).toUtc();
      _skew = serverUtc.difference(DateTime.now().toUtc());
    }
    _businessDate = body['business_date'] as String?;
    _timezone = body['timezone'] as String?;
    _localTime = body['local_time'] as String?;
  }

  static String shiftIsoDate(String iso, int dayDelta) {
    final parsed = DateTime.parse(iso);
    final shifted = DateTime(parsed.year, parsed.month, parsed.day).add(Duration(days: dayDelta));
    return _formatDate(shifted);
  }

  static String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
