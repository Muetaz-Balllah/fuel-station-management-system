import csv
import io
import uuid
from datetime import date, datetime, time, timedelta, timezone

from sqlmodel import Session, select

from assets.levels import station_timezone
from assets.models import Nozzle, Pump, Tank
from attendance.models import Attendance, ShiftAssignment, ShiftSession
from shifts.models import ShiftDuty, ShiftReading
from shifts.reconciliation import format_liters, format_money, q_liters, variance_label
from core.deps import permission_codes
from enums import PermissionCode
from errors import AppError
from stations.models import FuelProduct, ShiftTemplate, Station
from stations.windows import expand_window
from users.audit import write_audit
from users.models import User
from utils import as_utc, utcnow

STATUS_LABELS = {
    "assigned": "مكلّف",
    "present": "حاضر",
    "late": "متأخر",
    "absent": "غائب",
    "completed": "مكتمل",
}
_SHOWED = {"present", "late", "completed"}
_WEEKDAYS = ["الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت", "الأحد"]
_DUTY_STATUS_LABELS = {
    "open": "مفتوحة",
    "pending_approval": "بانتظار توقيع المشرف",
    "approved": "معتمدة",
    "rejected": "مرفوضة",
}


def schedule_window(session: Session, user: User, date_from: date, date_to: date) -> list[dict]:
    if date_to < date_from:
        raise AppError("VALIDATION_ERROR", "نهاية المدى قبل بدايته.", 422)
    templates = session.exec(
        select(ShiftTemplate)
        .where(ShiftTemplate.station_id == user.station_id)
        .order_by(ShiftTemplate.sort_order, ShiftTemplate.name_ar)
    ).all()
    sessions = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == user.station_id,
            ShiftSession.business_date >= date_from,
            ShiftSession.business_date <= date_to,
        )
    ).all()
    by_key = {(row.business_date, row.template_id): row for row in sessions}
    days = []
    cursor = date_from
    while cursor <= date_to:
        items = []
        for template in templates:
            shift = by_key.get((cursor, template.id))
            if shift is None:
                enabled = template.is_active
                items.append(
                    {
                        "template_id": str(template.id),
                        "template_name": template.name_ar,
                        "session_id": None,
                        "session_status": None,
                        "enabled": enabled,
                    }
                )
            else:
                items.append(
                    {
                        "template_id": str(template.id),
                        "template_name": template.name_ar,
                        "session_id": str(shift.id),
                        "session_status": shift.status,
                        "enabled": shift.status != "cancelled",
                    }
                )
        days.append({"date": cursor.isoformat(), "templates": items})
        cursor += timedelta(days=1)
    return days


def set_session_availability(session: Session, user: User, template_id: str, business_date: date, active: bool) -> dict:
    template = _template(session, user, template_id)
    if not template.is_active and active:
        raise AppError("TEMPLATE_INACTIVE", "هذا القالب متوقف في الإعدادات. فعّله أولاً.", 409)
    shift = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == user.station_id,
            ShiftSession.template_id == template.id,
            ShiftSession.business_date == business_date,
        )
    ).first()
    if not active:
        if shift is not None:
            busy = session.exec(
                select(ShiftDuty).where(
                    ShiftDuty.session_id == shift.id,
                    ShiftDuty.status.in_(["open", "pending_approval"]),  # type: ignore[attr-defined]
                )
            ).first()
            if busy is not None:
                raise AppError("DUTY_IN_PROGRESS", "لا يمكن تعطيل وردية فيها عهدة مفتوحة أو بانتظار الاعتماد.", 409)
            shift.status = "cancelled"
            shift.updated_at = utcnow()
            session.add(shift)
        else:
            station = session.get(Station, user.station_id)
            tz = station_timezone(station.timezone if station else "Africa/Tripoli")
            starts, ends = _window(template, business_date, tz)
            shift = ShiftSession(
                station_id=user.station_id,
                template_id=template.id,
                supervisor_id=user.id,
                code=_next_code(session, user.station_id, business_date.year),
                business_date=business_date,
                status="cancelled",
                starts_at=starts,
                ends_at=ends,
            )
            session.add(shift)
        write_audit(
            session,
            actor_id=user.id,
            action="session_disabled",
            entity="shift_session",
            entity_id=str(shift.id),
            detail={"business_date": business_date.isoformat(), "template_id": str(template.id)},
        )
        session.commit()
        session.refresh(shift)
        return _session_public(session, shift)
    if shift is None:
        from attendance.routes import SessionCreate

        return open_session(
            session,
            user,
            SessionCreate(template_id=str(template.id), business_date=business_date.isoformat()),
        )
    if shift.status == "cancelled":
        shift.status = "open"
        shift.updated_at = utcnow()
        session.add(shift)
        write_audit(
            session,
            actor_id=user.id,
            action="session_enabled",
            entity="shift_session",
            entity_id=str(shift.id),
            detail={"business_date": business_date.isoformat(), "template_id": str(template.id)},
        )
        session.commit()
        session.refresh(shift)
    return _session_public(session, shift)


def sweep_expired_sessions(session: Session, station_id: uuid.UUID) -> None:
    now = utcnow()
    rows = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == station_id,
            ShiftSession.status == "open",
            ShiftSession.ends_at < now,
        )
    ).all()
    changed = False
    for shift in rows:
        busy = session.exec(
            select(ShiftDuty).where(
                ShiftDuty.session_id == shift.id,
                ShiftDuty.status.in_(["open", "pending_approval", "rejected"]),  # type: ignore[attr-defined]
            )
        ).first()
        if busy is not None:
            continue
        shift.status = "closed"
        shift.updated_at = utcnow()
        session.add(shift)
        changed = True
    if changed:
        session.commit()


def list_sessions(session: Session, user: User, business_date: date | None) -> list[dict]:
    sweep_expired_sessions(session, user.station_id)
    statement = select(ShiftSession).where(ShiftSession.station_id == user.station_id)
    if business_date is not None:
        statement = statement.where(ShiftSession.business_date == business_date)
    rows = session.exec(statement.order_by(ShiftSession.starts_at)).all()
    return [_session_public(session, row) for row in rows]


def open_session(session: Session, user: User, payload) -> dict:
    business_date = _parse_date(payload.business_date)
    template = _template(session, user, payload.template_id)
    found = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == user.station_id,
            ShiftSession.template_id == template.id,
            ShiftSession.business_date == business_date,
        )
    ).first()
    if found is not None:
        if found.status == "cancelled":
            raise AppError("SESSION_CANCELLED", "هذه الوردية معطّلة لهذا اليوم. فعّلها من جدول التفعيل.", 409)
        return _session_public(session, found)
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    starts, ends = _window(template, business_date, tz)
    supervisor_id = _supervisor(session, user, payload.supervisor_id)
    row = ShiftSession(
        station_id=user.station_id,
        template_id=template.id,
        supervisor_id=supervisor_id,
        code=_next_code(session, user.station_id, business_date.year),
        business_date=business_date,
        status="open",
        starts_at=starts,
        ends_at=ends,
    )
    session.add(row)
    session.flush()
    write_audit(
        session,
        actor_id=user.id,
        action="session_opened",
        entity="shift_session",
        entity_id=str(row.id),
        detail={"code": row.code, "business_date": business_date.isoformat()},
    )
    session.commit()
    session.refresh(row)
    return _session_public(session, row)


def list_attendance(
    session: Session,
    user: User,
    session_id: uuid.UUID,
    page: int | None = None,
    page_size: int | None = None,
) -> dict:
    from core.pagination import page_bounds, slice_page

    shift = _shift(session, user, session_id)
    rows = session.exec(
        select(Attendance).where(Attendance.session_id == shift.id).order_by(Attendance.created_at)
    ).all()
    items = [_attendance_public(session, row, shift) for row in rows]
    safe_page, safe_size = page_bounds(page, page_size, default_size=10)
    sliced, total = slice_page(items, safe_page, safe_size)
    return {"items": sliced, "total": total, "page": safe_page, "page_size": safe_size}


def register_attendance(session: Session, actor: User, session_id: uuid.UUID, payload) -> dict:
    shift = _shift(session, actor, session_id)
    employee = _employee(session, actor, payload.user_id)
    existing = session.exec(
        select(Attendance).where(
            Attendance.session_id == shift.id,
            Attendance.user_id == employee.id,
        )
    ).first()
    if existing is not None:
        raise AppError(
            "ATTENDANCE_EXISTS",
            "هذا الموظف مسجّل في هذه الوردية. عدّل السجل بدل إنشاء سجل جديد.",
            409,
        )
    absent = payload.status == "absent"
    if absent and not (payload.note or "").strip():
        raise AppError("VALIDATION_ERROR", "اكتب سبب الغياب.", 422)
    if not absent and not payload.nozzle_ids:
        raise AppError("VALIDATION_ERROR", "اختر مسدساً واحداً على الأقل.", 422)
    check_in = None if absent else _clock(payload.check_in_at, shift.business_date, _tz(session, actor))
    status = "absent" if absent else _arrival_status(session, shift, check_in)
    row = Attendance(
        station_id=actor.station_id,
        session_id=shift.id,
        user_id=employee.id,
        recorded_by=actor.id,
        status=status,
        note=(payload.note or "").strip() or None,
        check_in_at=check_in,
    )
    session.add(row)
    session.flush()
    if not absent:
        _replace_nozzles(session, shift, row, payload.nozzle_ids)
    write_audit(
        session,
        actor_id=actor.id,
        action="attendance_registered",
        entity="attendance",
        entity_id=str(row.id),
        detail={"status": status, "user_id": str(employee.id)},
    )
    session.commit()
    session.refresh(row)
    return _attendance_public(session, row, shift)


def update_attendance(session: Session, actor: User, attendance_id: uuid.UUID, payload) -> dict:
    row = session.get(Attendance, attendance_id)
    if row is None or row.station_id != actor.station_id:
        raise AppError("ATTENDANCE_NOT_FOUND", "تعذر العثور على سجل الحضور.", 404)
    shift = _shift(session, actor, row.session_id)
    data = payload.model_dump(exclude_unset=True)
    tz = _tz(session, actor)
    if data.get("status") == "absent":
        if not (data.get("note") or row.note or "").strip():
            raise AppError("VALIDATION_ERROR", "اكتب سبب الغياب.", 422)
        row.status = "absent"
        row.check_in_at = None
        row.check_out_at = None
        _replace_nozzles(session, shift, row, [])
    else:
        if "nozzle_ids" in data and data["nozzle_ids"] is not None:
            if not data["nozzle_ids"]:
                raise AppError("VALIDATION_ERROR", "اختر مسدساً واحداً على الأقل.", 422)
            _replace_nozzles(session, shift, row, data["nozzle_ids"])
        if "check_in_at" in data:
            row.check_in_at = _clock(data["check_in_at"], shift.business_date, tz)
            if row.status != "completed":
                row.status = _arrival_status(session, shift, row.check_in_at)
        if "check_out_at" in data and data["check_out_at"]:
            if row.check_in_at is None:
                raise AppError("VALIDATION_ERROR", "لا يمكن تسجيل الانصراف قبل الحضور.", 422)
            row.check_out_at = _clock(data["check_out_at"], shift.business_date, tz)
            row.status = "completed"
        elif "status" in data and data["status"] in STATUS_LABELS and data["status"] != "absent":
            row.status = data["status"]
    if "note" in data:
        row.note = (data["note"] or "").strip() or None
    row.updated_at = utcnow()
    session.add(row)
    write_audit(
        session,
        actor_id=actor.id,
        action="attendance_updated",
        entity="attendance",
        entity_id=str(row.id),
        detail={"status": row.status},
    )
    session.commit()
    session.refresh(row)
    return _attendance_public(session, row, shift)


def attendance_csv(session: Session, user: User, session_id: uuid.UUID) -> str:
    rows = list_attendance(session, user, session_id, page=1, page_size=10_000)["items"]
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        ["الاسم", "المسمى", "الرقم الوظيفي", "المضخة", "المسدس", "الحضور", "الانصراف", "الحالة", "ملاحظة"]
    )
    for row in rows:
        pumps = " / ".join(item["pump_code"] for item in row["assignments"])
        nozzles = " / ".join(item["nozzle_code"] for item in row["assignments"])
        writer.writerow(
            [
                row["full_name"],
                row["job_title"],
                row["employee_code"],
                pumps,
                nozzles,
                row["check_in_label"] or "",
                row["check_out_label"] or "",
                row["status_label"],
                row["note"] or "",
            ]
        )
    return buffer.getvalue()


def summary(session: Session, user: User, business_date: date) -> dict:
    shifts = session.exec(
        select(ShiftSession).where(
            ShiftSession.station_id == user.station_id,
            ShiftSession.business_date == business_date,
        )
    ).all()
    morning = _morning_session(session, shifts)
    morning_rows = _rows_for(session, morning.id) if morning else []
    showed = sum(1 for row in morning_rows if row.status in _SHOWED)
    total = len(morning_rows)
    covered = _covered_nozzles(session, morning_rows)
    active = _active_nozzle_count(session, user.station_id)
    template = session.get(ShiftTemplate, morning.template_id) if morning else None
    late = sum(1 for row in morning_rows if row.status == "late")
    return {
        "date": business_date.isoformat(),
        "session_id": str(morning.id) if morning else None,
        "template_name": template.name_ar if template else "",
        "morning": {
            "showed": showed,
            "total": total,
            "percent": _percent(showed, total),
        },
        "coverage": {
            "covered": covered,
            "active": active,
            "label": "مسدس نشط",
        },
        "late_count": late,
        "week": _week(session, user, business_date),
    }


def options(session: Session, user: User) -> dict:
    templates = session.exec(
        select(ShiftTemplate)
        .where(ShiftTemplate.station_id == user.station_id, ShiftTemplate.is_active == True)  # noqa: E712
        .order_by(ShiftTemplate.sort_order)
    ).all()
    users = session.exec(
        select(User).where(User.station_id == user.station_id, User.is_active == True).order_by(User.full_name)  # noqa: E712
    ).all()
    nozzles = session.exec(select(Nozzle).where(Nozzle.station_id == user.station_id).order_by(Nozzle.code)).all()
    return {
        "templates": [
            {
                "id": str(item.id),
                "name_ar": item.name_ar,
                "starts_at": _clock_label(_as_time(item.starts_at)),
                "ends_at": _clock_label(_as_time(item.ends_at)),
                "grace_minutes": item.grace_minutes,
                "crosses_midnight": _as_time(item.ends_at) <= _as_time(item.starts_at),
            }
            for item in templates
        ],
        "users": [
            {
                "id": str(item.id),
                "full_name": item.full_name,
                "job_title": item.job_title,
                "employee_code": item.employee_code,
            }
            for item in users
        ],
        "nozzles": [_nozzle_choice(session, item) for item in nozzles],
    }


def _session_public(session: Session, row: ShiftSession) -> dict:
    template = session.get(ShiftTemplate, row.template_id)
    starts = _as_time(template.starts_at) if template else time(0, 0)
    ends = _as_time(template.ends_at) if template else time(0, 0)
    return {
        "id": str(row.id),
        "code": row.code,
        "template_id": str(row.template_id),
        "template_name": template.name_ar if template else "",
        "business_date": row.business_date.isoformat(),
        "status": row.status,
        "starts_at": _iso(as_utc(row.starts_at)),
        "ends_at": _iso(as_utc(row.ends_at)),
        "crosses_midnight": ends <= starts,
        "grace_minutes": template.grace_minutes if template else 0,
    }


def _attendance_public(session: Session, row: Attendance, shift: ShiftSession) -> dict:
    employee = session.get(User, row.user_id)
    tz = _tz_for_station(session, row.station_id)
    assignments = session.exec(
        select(ShiftAssignment).where(ShiftAssignment.attendance_id == row.id)
    ).all()
    return {
        "id": str(row.id),
        "session_id": str(row.session_id),
        "user_id": str(row.user_id),
        "full_name": employee.full_name if employee else "",
        "job_title": employee.job_title if employee else "",
        "employee_code": employee.employee_code if employee else "",
        "status": row.status,
        "status_label": STATUS_LABELS.get(row.status, row.status),
        "note": row.note,
        "check_in_at": _iso(as_utc(row.check_in_at)),
        "check_out_at": _iso(as_utc(row.check_out_at)),
        "check_in_label": _local_clock(row.check_in_at, tz),
        "check_out_label": _local_clock(row.check_out_at, tz),
        "assignments": [_assignment_public(session, item) for item in assignments],
        "duty": _duty_snapshot(session, row.id, tz),
    }


def _duty_snapshot(session: Session, attendance_id: uuid.UUID, tz) -> dict | None:
    duty = session.exec(
        select(ShiftDuty)
        .where(ShiftDuty.attendance_id == attendance_id)
        .order_by(ShiftDuty.opened_at.desc())
    ).first()
    if duty is None:
        return None
    readings = session.exec(select(ShiftReading).where(ShiftReading.duty_id == duty.id)).all()
    liters = q_liters(0)
    for row in readings:
        if row.liters is not None:
            liters = q_liters(liters + q_liters(row.liters))
    line_rows = []
    for reading in readings:
        nozzle = session.get(Nozzle, reading.nozzle_id)
        pump = session.get(Pump, nozzle.pump_id) if nozzle else None
        tank = session.get(Tank, pump.tank_id) if pump else None
        product = session.get(FuelProduct, tank.product_id) if tank else None
        line_rows.append(
            {
                "pump_code": pump.code if pump else "",
                "nozzle_code": nozzle.code if nozzle else "",
                "opening_meter": format_liters(reading.opening_meter),
                "closing_meter": format_liters(reading.closing_meter) if reading.closing_meter is not None else None,
                "liters": format_liters(reading.liters) if reading.liters is not None else None,
                "line_amount": format_money(reading.line_amount) if reading.line_amount is not None else None,
                "product_name": product.name_ar if product else "",
            }
        )
    closed = duty.submitted_at or duty.approved_at
    return {
        "id": str(duty.id),
        "status": duty.status,
        "status_label": _DUTY_STATUS_LABELS.get(duty.status, duty.status),
        "opened_label": _local_clock(duty.opened_at, tz),
        "submitted_label": _local_clock(duty.submitted_at, tz),
        "work_hours_label": _work_hours_label_attendance(duty.opened_at, closed, tz),
        "liters": format_liters(liters) if duty.status != "open" else None,
        "expected_cash": format_money(duty.expected_cash) if duty.expected_cash is not None else None,
        "cash_handed": format_money(duty.cash_handed) if duty.cash_handed is not None else None,
        "variance_label": variance_label(duty.variance) if duty.variance is not None else None,
        "lines": line_rows,
    }


def _work_hours_label_attendance(opened, closed, tz) -> str | None:
    if opened is None:
        return None
    start_text = _local_clock(opened, tz)
    if closed is None:
        return f"من {start_text}" if start_text else None
    end_text = _local_clock(closed, tz)
    if not start_text or not end_text:
        return None
    start = as_utc(opened)
    end = as_utc(closed)
    if start is None or end is None:
        return f"{start_text} – {end_text}"
    delta_seconds = int((end - start).total_seconds())
    if delta_seconds < 0:
        return f"{start_text} – {end_text}"
    hours = delta_seconds // 3600
    minutes = (delta_seconds % 3600) // 60
    duration = f"{hours}س {minutes}د" if hours > 0 else f"{minutes}د"
    return f"{start_text} – {end_text} · {duration}"


def _assignment_public(session: Session, row: ShiftAssignment) -> dict:
    nozzle = session.get(Nozzle, row.nozzle_id)
    pump = session.get(Pump, nozzle.pump_id) if nozzle else None
    tank = session.get(Tank, pump.tank_id) if pump else None
    product = session.get(FuelProduct, tank.product_id) if tank else None
    return {
        "id": str(row.id),
        "nozzle_id": str(row.nozzle_id),
        "nozzle_code": nozzle.code if nozzle else "",
        "label": nozzle.label if nozzle else "",
        "pump_code": pump.code if pump else "",
        "product_name": product.name_ar if product else "",
    }


def _replace_nozzles(session: Session, shift: ShiftSession, attendance: Attendance, nozzle_ids: list[str]) -> None:
    wanted: list[uuid.UUID] = []
    for raw in nozzle_ids:
        nozzle = _nozzle(session, shift.station_id, raw)
        pump = session.get(Pump, nozzle.pump_id)
        if pump is None or pump.status != "active":
            raise AppError(
                "PUMP_UNAVAILABLE",
                "لا يمكن تكليف مسدس على مضخة متوقفة أو قيد الصيانة.",
                409,
            )
        taken = session.exec(
            select(ShiftAssignment).where(
                ShiftAssignment.session_id == shift.id,
                ShiftAssignment.nozzle_id == nozzle.id,
            )
        ).first()
        if taken is not None and taken.attendance_id != attendance.id:
            raise AppError(
                "NOZZLE_TAKEN",
                "هذا المسدس مكلّف لموظف آخر في نفس الوردية.",
                409,
            )
        if nozzle.id not in wanted:
            wanted.append(nozzle.id)
    current = session.exec(
        select(ShiftAssignment).where(ShiftAssignment.attendance_id == attendance.id)
    ).all()
    for row in current:
        if row.nozzle_id not in wanted:
            session.delete(row)
    session.flush()
    held = {row.nozzle_id for row in current if row.nozzle_id in wanted}
    for nozzle_id in wanted:
        if nozzle_id in held:
            continue
        session.add(
            ShiftAssignment(
                station_id=shift.station_id,
                session_id=shift.id,
                attendance_id=attendance.id,
                nozzle_id=nozzle_id,
            )
        )


def _arrival_status(session: Session, shift: ShiftSession, check_in: datetime | None) -> str:
    if check_in is None:
        return "assigned"
    template = session.get(ShiftTemplate, shift.template_id)
    grace = template.grace_minutes if template else 0
    start = as_utc(shift.starts_at)
    if start is None:
        return "present"
    if as_utc(check_in) <= start + timedelta(minutes=grace):
        return "present"
    return "late"


def _window(template: ShiftTemplate, business_date: date, tz) -> tuple[datetime, datetime]:
    starts = _as_time(template.starts_at)
    ends = _as_time(template.ends_at)
    start_naive, end_naive = expand_window(starts, ends, business_date)
    start = datetime.combine(start_naive.date(), start_naive.time(), tzinfo=tz)
    end = datetime.combine(end_naive.date(), end_naive.time(), tzinfo=tz)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def _morning_session(session: Session, shifts: list[ShiftSession]) -> ShiftSession | None:
    if not shifts:
        return None
    named = []
    early = []
    for row in shifts:
        template = session.get(ShiftTemplate, row.template_id)
        if template and "صباح" in template.name_ar:
            named.append(row)
        start = _as_time(template.starts_at) if template else time(0, 0)
        if start.hour < 12:
            early.append(row)
    if named:
        return named[0]
    if early:
        return early[0]
    return shifts[0]


def _rows_for(session: Session, session_id: uuid.UUID) -> list[Attendance]:
    return list(session.exec(select(Attendance).where(Attendance.session_id == session_id)).all())


def _covered_nozzles(session: Session, rows: list[Attendance]) -> int:
    ids = [row.id for row in rows if row.status in {"present", "late"}]
    if not ids:
        return 0
    assignments = session.exec(
        select(ShiftAssignment).where(ShiftAssignment.attendance_id.in_(ids))  # type: ignore[attr-defined]
    ).all()
    return len({item.nozzle_id for item in assignments})


def _active_nozzle_count(session: Session, station_id: uuid.UUID) -> int:
    pumps = session.exec(
        select(Pump).where(Pump.station_id == station_id, Pump.status == "active")
    ).all()
    if not pumps:
        return 0
    pump_ids = [item.id for item in pumps]
    nozzles = session.exec(select(Nozzle).where(Nozzle.pump_id.in_(pump_ids))).all()  # type: ignore[attr-defined]
    return len(nozzles)


def _week(session: Session, user: User, business_date: date) -> list[dict]:
    offset = (business_date.weekday() - 5) % 7
    start = business_date - timedelta(days=offset)
    days = []
    for index in range(7):
        day = start + timedelta(days=index)
        rows = session.exec(
            select(Attendance)
            .join(ShiftSession, ShiftSession.id == Attendance.session_id)
            .where(
                Attendance.station_id == user.station_id,
                ShiftSession.business_date == day,
            )
        ).all()
        showed = sum(1 for row in rows if row.status in {"present", "late", "completed"})
        absent = sum(1 for row in rows if row.status == "absent")
        days.append(
            {
                "date": day.isoformat(),
                "label": _WEEKDAYS[day.weekday()],
                "percent": _percent(showed, showed + absent) if showed + absent else None,
            }
        )
    return days


def _template(session: Session, user: User, template_id: str) -> ShiftTemplate:
    try:
        parsed = uuid.UUID(template_id)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "الوردية غير صالحة.", 422) from exc
    template = session.get(ShiftTemplate, parsed)
    if template is None or template.station_id != user.station_id:
        raise AppError("TEMPLATE_NOT_FOUND", "تعذر العثور على الوردية.", 404)
    return template


def _shift(session: Session, user: User, session_id: uuid.UUID) -> ShiftSession:
    row = session.get(ShiftSession, session_id)
    if row is None or row.station_id != user.station_id:
        raise AppError("SESSION_NOT_FOUND", "تعذر العثور على الوردية.", 404)
    return row


def _employee(session: Session, actor: User, user_id: str) -> User:
    try:
        parsed = uuid.UUID(user_id)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "الموظف غير صالح.", 422) from exc
    employee = session.get(User, parsed)
    if employee is None or employee.station_id != actor.station_id:
        raise AppError("USER_NOT_FOUND", "تعذر العثور على الموظف.", 404)
    if not employee.is_active:
        raise AppError("ACCOUNT_INACTIVE", "هذا الحساب غير نشط.", 422)
    return employee


def _nozzle(session: Session, station_id: uuid.UUID, nozzle_id: str) -> Nozzle:
    try:
        parsed = uuid.UUID(nozzle_id)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "المسدس غير صالح.", 422) from exc
    nozzle = session.get(Nozzle, parsed)
    if nozzle is None or nozzle.station_id != station_id:
        raise AppError("NOZZLE_NOT_FOUND", "تعذر العثور على المسدس.", 404)
    return nozzle


def _nozzle_choice(session: Session, nozzle: Nozzle) -> dict:
    pump = session.get(Pump, nozzle.pump_id)
    tank = session.get(Tank, pump.tank_id) if pump else None
    product = session.get(FuelProduct, tank.product_id) if tank else None
    return {
        "id": str(nozzle.id),
        "code": nozzle.code,
        "label": nozzle.label,
        "pump_code": pump.code if pump else "",
        "pump_status": pump.status if pump else "",
        "product_name": product.name_ar if product else "",
    }


def _supervisor(session: Session, actor: User, supervisor_id: str | None) -> uuid.UUID | None:
    if not supervisor_id:
        return None
    supervisor = _employee(session, actor, supervisor_id)
    if PermissionCode.SHIFTS_APPROVE not in permission_codes(session, supervisor.role_id):
        raise AppError("VALIDATION_ERROR", "المشرف يجب أن يملك صلاحية اعتماد الورديات.", 422)
    return supervisor.id


def _next_code(session: Session, station_id: uuid.UUID, year: int) -> str:
    prefix = f"SH-{year}-"
    rows = session.exec(select(ShiftSession.code).where(ShiftSession.station_id == station_id)).all()
    numbers = []
    for code in rows:
        if isinstance(code, str) and code.startswith(prefix):
            try:
                numbers.append(int(code[len(prefix) :]))
            except ValueError:
                continue
    return f"{prefix}{(max(numbers) if numbers else 0) + 1:03d}"


def _clock(value: str | None, business_date: date, tz) -> datetime | None:
    if value is None or not str(value).strip():
        return None
    text = str(value).strip()
    if "T" not in text and len(text) <= 5 and ":" in text:
        parts = text.split(":")
        try:
            local = datetime.combine(business_date, time(int(parts[0]), int(parts[1])), tzinfo=tz)
        except ValueError as exc:
            raise AppError("VALIDATION_ERROR", "صيغة الوقت يجب أن تكون ساعة:دقيقة.", 422) from exc
        return local.astimezone(timezone.utc)
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة الوقت يجب أن تكون ساعة:دقيقة.", 422) from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=tz)
    return parsed.astimezone(timezone.utc)


def _tz(session: Session, user: User):
    return _tz_for_station(session, user.station_id)


def _tz_for_station(session: Session, station_id: uuid.UUID):
    station = session.get(Station, station_id)
    return station_timezone(station.timezone if station else "Africa/Tripoli")


def _as_time(value: time | str) -> time:
    if isinstance(value, time):
        return value
    parts = str(value).split(":")
    return time(int(parts[0]), int(parts[1]))


def _clock_label(value: time) -> str:
    return f"{value.hour:02d}:{value.minute:02d}"


def _local_clock(value: datetime | None, tz) -> str | None:
    moment = as_utc(value)
    if moment is None:
        return None
    local = moment.astimezone(tz)
    return f"{local.hour:02d}:{local.minute:02d}"


def _parse_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة التاريخ يجب أن تكون سنة-شهر-يوم.", 422) from exc


def _percent(part: int, whole: int) -> int:
    if whole <= 0:
        return 0
    return int(round(part * 100 / whole))


def _iso(moment: datetime | None) -> str | None:
    if moment is None:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat()
