from datetime import date, datetime, time, timedelta


def expand_window(starts: time, ends: time, business_date: date) -> tuple[datetime, datetime]:
    """Turn a template clock into a concrete window.

    An end that is equal to or earlier than the start belongs to the next day,
    so 16:00–00:00 is an overnight shift.
    """
    end_date = business_date + timedelta(days=1) if ends <= starts else business_date
    return datetime.combine(business_date, starts), datetime.combine(end_date, ends)
