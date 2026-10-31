from datetime import date, datetime, time

from stations.windows import expand_window


def test_morning_shift_ends_the_same_day():
    start, end = expand_window(time(8, 0), time(16, 0), date(2026, 10, 31))
    assert start == datetime(2026, 10, 31, 8, 0)
    assert end == datetime(2026, 10, 31, 16, 0)


def test_shift_ending_at_midnight_ends_the_next_day():
    start, end = expand_window(time(16, 0), time(0, 0), date(2026, 10, 31))
    assert start == datetime(2026, 10, 31, 16, 0)
    assert end == datetime(2026, 11, 1, 0, 0)
