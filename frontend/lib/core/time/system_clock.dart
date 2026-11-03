import 'package:dio/dio.dart';

/// Server-authoritative clock; business dates must not follow the device clock.
class SystemClock {
  SystemClock._();

  static Duration _skew = Duration.zero;
  static String? _businessDate;
  static String? _timezone;
  static String? _localTime;
  static DateTime? _utcAtSync;
  static DateTime? _localWallAtSync;

  static String? get businessDate => _businessDate;
  static String? get timezone => _timezone;
  static String? get localTime => _localTime;

  /// Station wall clock (HH:mm), advanced between server syncs using UTC skew.
  static String? get localTimeNow {
    if (_localWallAtSync != null && _utcAtSync != null) {
      final tick = _localWallAtSync!.add(nowUtc().difference(_utcAtSync!));
      final h = tick.hour.toString().padLeft(2, '0');
      final m = tick.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return _localTime;
  }

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
    DateTime? serverUtc;
    if (utcRaw != null) {
      serverUtc = DateTime.parse(utcRaw).toUtc();
      _skew = serverUtc.difference(DateTime.now().toUtc());
    }
    _businessDate = body['business_date'] as String?;
    _timezone = body['timezone'] as String?;
    _localTime = body['local_time'] as String?;
    _utcAtSync = serverUtc;
    final day = _businessDate;
    final hm = _localTime;
    if (day != null && hm != null && hm.isNotEmpty) {
      _localWallAtSync = DateTime.parse('${day}T$hm:00');
    } else {
      _localWallAtSync = null;
    }
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
