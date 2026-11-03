import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlmodel import Session, select

from alerts import note_tank_crossing
from assets.levels import station_timezone
from assets.models import InventoryMovement, Nozzle, Pump, Tank
from attendance.models import Attendance, ShiftAssignment, ShiftSession
from errors import AppError
from shifts.models import Notification, ShiftDuty, ShiftReading
from shifts.reconciliation import (
    format_liters,
    format_money,
    format_price,
    q_liters,
    q_money,
    reconcile,
    rollup,
    variance_label,
)
from stations.models import FuelPrice, FuelProduct, ShiftTemplate, Station
from users.audit import write_audit
from users.models import Permission, RolePermission, User
from utils import as_utc, utcnow

_OPEN_STATUSES = {"present", "late", "assigned"}
_STATUS_LABELS = {
    "open": "مفتوحة",
    "pending_approval": "بانتظار توقيع المشرف",
    "approved": "معتمدة",
    "rejected": "مرفوضة",
}
_SESSION_LABELS = {
    "open": "جارية الآن",
    "approved": "معتمدة ومغلقة",
    "cancelled": "معطّلة",
    "closed": "منتهية",
}


def my_assignment(session: Session, user: User) -> dict:
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    today = datetime.now(tz).date()
    identity = _identity(user)
    active_duty, active_shift = _active_duty_today(session, user, today)
    if active_duty is not None and active_shift is not None:
        attendance = session.get(Attendance, active_duty.attendance_id)
        nozzles = _assigned_nozzles(session, attendance) if attendance is not None else []
        return {
            "date": today.isoformat(),
            "can_open": False,
            "self_service": False,
            "reason": None,
            "session": _session_brief(session, active_shift),
            "shifts": [],
            "identity": identity,
            "attendance_status": attendance.status if attendance is not None else None,
            "duty": _duty_public(session, active_duty),
            "nozzles": nozzles,
        }
    rows = session.exec(
        select(Attendance, ShiftSession)
        .join(ShiftSession, ShiftSession.id == Attendance.session_id)
        .where(Attendance.user_id == user.id, ShiftSession.business_date == today)
    ).all()
    if rows and all(attendance.status == "absent" for attendance, _shift in rows):
        shift = rows[0][1]
        body = _empty(today, "تم تسجيل غيابك لهذه الوردية، ولا يمكن فتح العهدة.", shift)
        body["self_service"] = False
        body["shifts"] = []
        body["identity"] = identity
        return body
    attendance, shift = _pick_attendance(session, user, today)
    shifts = _operator_shifts(session, user, today)
    claimable = [item for item in shifts if item["claimable"]]
    nozzles = _station_nozzles(session, user)
    ready = [item for item in nozzles if item["selectable"]]
    reason = None
    if not claimable:
        reason = "لا توجد وردية متاحة للفتح الآن." if shifts else "لا توجد ورديات مجدولة لهذا اليوم."
    elif not ready:
        reason = "لا توجد مضخة جاهزة لفتح وردية عليها."
    return {
        "date": today.isoformat(),
        "can_open": bool(claimable) and bool(ready),
        "self_service": True,
        "reason": reason,
        "session": _session_brief(session, shift) if shift is not None else None,
        "shifts": shifts,
        "identity": identity,
        "attendance_status": attendance.status if attendance is not None else None,
        "duty": None,
        "nozzles": nozzles,
    }


def open_duty(session: Session, user: User, payload, permissions: tuple[str, ...]) -> dict:
    shift = _resolve_shift(session, user, payload)
    attendance = session.exec(
        select(Attendance).where(
            Attendance.session_id == shift.id,
            Attendance.user_id == user.id,
        )
    ).first()
    rostered_id = None
    if attendance is None:
        attendance, rostered_id = _self_claim(session, user, shift, payload)
    else:
        rostered_id = _align_worker_assignments(session, user, shift, attendance, payload)
    if attendance.status == "absent":
        raise AppError("ATTENDANCE_BLOCKED", "تم تسجيل غيابك لهذه الوردية، ولا يمكن فتح العهدة.", 409)
    if attendance.status not in _OPEN_STATUSES:
        raise AppError("ATTENDANCE_BLOCKED", "لا يمكن فتح الوردية قبل تسجيل الحضور.", 409)
    existing = _duty_for(session, shift.id, user.id)
    if existing is not None:
        raise AppError("DUTY_EXISTS", "هذه الوردية مفتوحة بالفعل.", 409)
    if not payload.nozzles:
        raise AppError("NOZZLES_INCOMPLETE", "اختر مسدساً واحداً على الأقل لفتح الوردية.", 422)
    requested = []
    for item in payload.nozzles:
        nozzle_id = _uuid(item.nozzle_id, "المسدس غير معروف.")
        requested.append(nozzle_id)
    if len(set(requested)) != len(requested):
        raise AppError("NOZZLE_BUSY", "لا يمكن تكرار المسدس في الوردية نفسها.", 409)
    override = "meter.override" in permissions
    mismatched = False
    prepared = []
    for item in payload.nozzles:
        nozzle_id = _uuid(item.nozzle_id, "المسدس غير معروف.")
        nozzle, pump = _nozzle_pump(session, nozzle_id)
        if pump.status == "maintenance":
            raise AppError("PUMP_UNAVAILABLE", "المضخة في الصيانة ولا يمكن فتح وردية عليها.", 409)
        if nozzle.status != "ready":
            raise AppError("NOZZLE_UNAVAILABLE", "المسدس غير جاهز للتشغيل.", 409)
        _ensure_free(session, nozzle.id)
        opening = _meter(item.opening_meter)
        if opening != q_liters(nozzle.current_meter):
            mismatched = True
            if not override:
                raise AppError(
                    "METER_MISMATCH",
                    "قراءة الافتتاح لا تطابق آخر إغلاق للعداد.",
                    409,
                )
        price = _price_for_nozzle(session, nozzle)
        prepared.append((nozzle, opening, price))
    if mismatched:
        reason = (payload.reason or "").strip()
        if not reason:
            raise AppError("REASON_REQUIRED", "اكتب سبب تعديل قراءة الافتتاح.", 422)
    duty = ShiftDuty(
        station_id=user.station_id,
        session_id=shift.id,
        user_id=user.id,
        attendance_id=attendance.id,
        rostered_user_id=rostered_id,
        status="open",
        opened_at=utcnow(),
    )
    session.add(duty)
    session.flush()
    for nozzle, opening, price in prepared:
        session.add(
            ShiftReading(
                duty_id=duty.id,
                nozzle_id=nozzle.id,
                price_id=price.id,
                opening_meter=opening,
                unit_price=q_liters(price.price_per_liter),
            )
        )
    if attendance.check_in_at is None:
        attendance.check_in_at = utcnow()
        attendance.updated_at = utcnow()
    if attendance.status == "assigned":
        attendance.status = "present"
        attendance.updated_at = utcnow()
    session.add(attendance)
    write_audit(
        session,
        actor_id=user.id,
        action="duty_opened",
        entity="shift_duty",
        entity_id=str(duty.id),
        detail={"reason": (payload.reason or "").strip() or None},
    )
    session.commit()
    session.refresh(duty)
    return _duty_public(session, duty)


def get_duty(session: Session, user: User, duty_id: str, permissions: tuple[str, ...]) -> dict:
    duty = _duty(session, user, duty_id)
    if duty.user_id != user.id and "shifts.view_all" not in permissions and "shifts.approve" not in permissions:
        raise AppError("FORBIDDEN", "ليست لديك صلاحية لتنفيذ هذا الإجراء.", 403)
    return _duty_public(session, duty)


def close_duty(session: Session, user: User, duty_id: str, payload, permissions: tuple[str, ...]) -> dict:
    duty = _duty(session, user, duty_id)
    if duty.user_id != user.id:
        raise AppError("FORBIDDEN", "إغلاق العهدة متاح لصاحب الوردية فقط.", 403)
    if duty.status not in {"open", "rejected"}:
        raise AppError("DUTY_CLOSED", "هذه الوردية ليست مفتوحة للإغلاق.", 409)
    readings = _readings(session, duty.id)
    by_nozzle = {row.nozzle_id: row for row in readings}
    if len(payload.lines) != len(by_nozzle):
        raise AppError("NOZZLES_INCOMPLETE", "أدخل قراءة الإغلاق لكل مسدس في الوردية.", 422)
    seen: set[uuid.UUID] = set()
    lines = []
    for item in payload.lines:
        nozzle_id = _uuid(item.nozzle_id, "المسدس غير معروف.")
        reading = by_nozzle.get(nozzle_id)
        if reading is None:
            raise AppError("NOT_ASSIGNED", "هذا المسدس ليس ضمن الوردية المفتوحة.", 409)
        if nozzle_id in seen:
            raise AppError("NOZZLE_BUSY", "لا يمكن تكرار المسدس في الإغلاق.", 409)
        seen.add(nozzle_id)
        closing = _meter(item.closing_meter)
        rollover = bool(item.rollover)
        rollover_at = None
        if rollover:
            if "meter.override" not in permissions:
                raise AppError("FORBIDDEN", "تجاوز العداد متاح للمدير فقط.", 403)
            if not item.meter_rollover_at:
                raise AppError("VALIDATION_ERROR", "حدد سقف العداد عند الالتفاف.", 422)
            rollover_at = _meter(item.meter_rollover_at)
        elif closing < q_liters(reading.opening_meter):
            raise AppError("METER_REGRESSION", "قراءة الإغلاق أقل من قراءة الافتتاح.", 422)
        lines.append(
            {
                "nozzle_id": str(nozzle_id),
                "opening": reading.opening_meter,
                "closing": closing,
                "unit_price": reading.unit_price,
                "rollover": rollover,
                "rollover_at": rollover_at,
                "reading": reading,
            }
        )
    try:
        figures = reconcile(lines, _cash(payload.cash_handed))
    except ValueError as exc:
        raise AppError("METER_REGRESSION", "قراءة الإغلاق أقل من قراءة الافتتاح.", 422) from exc
    if duty.status == "rejected":
        write_audit(
            session,
            actor_id=user.id,
            action="duty_resubmitted",
            entity="shift_duty",
            entity_id=str(duty.id),
            detail={
                "expected_cash": format_money(duty.expected_cash) if duty.expected_cash is not None else None,
                "cash_handed": format_money(duty.cash_handed) if duty.cash_handed is not None else None,
                "variance": format_money(duty.variance) if duty.variance is not None else None,
            },
        )
    amounts = {line["nozzle_id"]: line for line in figures["lines"]}
    for line in lines:
        reading = line["reading"]
        amount = amounts[str(reading.nozzle_id)]
        reading.closing_meter = q_liters(line["closing"])
        reading.liters = amount["liters"]
        reading.line_amount = amount["line_amount"]
        reading.rollover = line["rollover"]
        reading.rollover_at = line["rollover_at"]
        session.add(reading)
    duty.status = "pending_approval"
    duty.submitted_at = utcnow()
    duty.cash_handed = figures["cash_handed"]
    duty.expected_cash = figures["expected_cash"]
    duty.variance = figures["variance"]
    duty.reject_reason = None
    duty.updated_at = utcnow()
    session.add(duty)
    attendance = session.get(Attendance, duty.attendance_id)
    if attendance is not None:
        stamp = utcnow()
        attendance.check_out_at = stamp
        if attendance.status not in {"absent"}:
            attendance.status = "completed"
        attendance.updated_at = stamp
        session.add(attendance)
    _notify_approvers(session, user, duty)
    session.commit()
    session.refresh(duty)
    return _close_public(session, duty, figures)


def approve_duty(session: Session, user: User, duty_id: str) -> dict:
    duty = _duty(session, user, duty_id)
    if duty.status != "pending_approval":
        raise AppError("DUTY_CLOSED", "لا يمكن اعتماد وردية ليست بانتظار التوقيع.", 409)
    readings = _readings(session, duty.id)
    figures = _stored_figures(duty, readings)
    if not _figures_match(duty, figures):
        raise AppError("RECONCILE_MISMATCH", "أرقام الإغلاق لا تطابق المحضر المحفوظ.", 409)
    tanks: dict[uuid.UUID, list[tuple[ShiftReading, Tank, Decimal]]] = {}
    for reading in readings:
        nozzle, pump = _nozzle_pump(session, reading.nozzle_id)
        tank = _lock_tank(session, pump.tank_id)
        liters = q_liters(reading.liters or 0)
        tanks.setdefault(tank.id, []).append((reading, tank, liters))
        _ = nozzle
    for group in tanks.values():
        tank = group[0][1]
        needed = q_liters(sum((item[2] for item in group), Decimal("0")))
        if needed > q_liters(tank.current_liters):
            raise AppError(
                "TANK_SHORT",
                "كمية البيع أكبر من رصيد الخزان. الوردية تبقى بانتظار التوقيع.",
                409,
            )
    for group in tanks.values():
        tank = group[0][1]
        before = q_liters(tank.current_liters)
        balance = before
        for reading, _, liters in group:
            balance = q_liters(balance - liters)
            session.add(
                InventoryMovement(
                    station_id=duty.station_id,
                    tank_id=tank.id,
                    nozzle_id=reading.nozzle_id,
                    movement_type="shift_sale",
                    liters_delta=-liters,
                    balance_after=balance,
                    source_type="duty",
                    source_id=str(duty.id),
                    note="اعتماد وردية",
                    created_by=user.id,
                )
            )
            nozzle = session.get(Nozzle, reading.nozzle_id)
            if nozzle is not None:
                nozzle.current_meter = q_liters(reading.closing_meter or nozzle.current_meter)
                nozzle.updated_at = utcnow()
                session.add(nozzle)
        tank.current_liters = balance
        tank.updated_at = utcnow()
        session.add(tank)
        note_tank_crossing(session, tank, before, balance)
    duty.status = "approved"
    duty.approved_at = utcnow()
    duty.approved_by = user.id
    duty.updated_at = utcnow()
    session.add(duty)
    _maybe_close_session(session, duty.session_id)
    write_audit(
        session,
        actor_id=user.id,
        action="duty_approved",
        entity="shift_duty",
        entity_id=str(duty.id),
        detail={"expected_cash": format_money(duty.expected_cash), "variance": format_money(duty.variance)},
    )
    session.commit()
    session.refresh(duty)
    return _duty_public(session, duty)


def reject_duty(session: Session, user: User, duty_id: str, reason: str) -> dict:
    from alerts import note_duty_rejected

    note = reason.strip()
    if not note:
        raise AppError("VALIDATION_ERROR", "اكتب سبب الرفض.", 422)
    duty = _duty(session, user, duty_id)
    if duty.status != "pending_approval":
        raise AppError("DUTY_CLOSED", "لا يمكن رفض وردية ليست بانتظار التوقيع.", 409)
    write_audit(
        session,
        actor_id=user.id,
        action="duty_rejected",
        entity="shift_duty",
        entity_id=str(duty.id),
        detail={
            "reason": note,
            "expected_cash": format_money(duty.expected_cash) if duty.expected_cash is not None else None,
            "cash_handed": format_money(duty.cash_handed) if duty.cash_handed is not None else None,
            "variance": format_money(duty.variance) if duty.variance is not None else None,
        },
    )
    duty.status = "rejected"
    duty.reject_reason = note
    duty.approved_by = None
    duty.approved_at = None
    duty.updated_at = utcnow()
    session.add(duty)
    note_duty_rejected(session, duty, note)
    session.commit()
    session.refresh(duty)
    return _duty_public(session, duty)


def my_duties(
    session: Session,
    user: User,
    page: int | None = None,
    page_size: int | None = None,
) -> dict:
    from core.pagination import page_bounds, slice_page

    rows = session.exec(
        select(ShiftDuty)
        .where(ShiftDuty.user_id == user.id, ShiftDuty.station_id == user.station_id)
        .order_by(ShiftDuty.opened_at.desc())
    ).all()
    items = [_duty_public(session, row) for row in rows]
    safe_page, safe_size = page_bounds(page, page_size, default_size=10)
    sliced, total = slice_page(items, safe_page, safe_size)
    return {"items": sliced, "total": total, "page": safe_page, "page_size": safe_size}


def duties_for_business_date(
    session: Session,
    user: User,
    business_date: date,
    page: int | None = None,
    page_size: int | None = None,
) -> dict:
    from core.pagination import page_bounds, slice_page

    rows = session.exec(
        select(ShiftDuty)
        .join(ShiftSession, ShiftSession.id == ShiftDuty.session_id)
        .where(
            ShiftDuty.station_id == user.station_id,
            ShiftSession.business_date == business_date,
        )
        .order_by(ShiftDuty.opened_at.desc())
    ).all()
    items = [_duty_public(session, row) for row in rows]
    safe_page, safe_size = page_bounds(page, page_size, default_size=10)
    sliced, total = slice_page(items, safe_page, safe_size)
    return {"items": sliced, "total": total, "page": safe_page, "page_size": safe_size}


def session_duties(
    session: Session,
    user: User,
    session_id: str,
    page: int | None = None,
    page_size: int | None = None,
) -> dict:
    from core.pagination import page_bounds, slice_page

    shift = _session_row(session, user, session_id)
    rows = session.exec(
        select(ShiftDuty).where(ShiftDuty.session_id == shift.id).order_by(ShiftDuty.opened_at.desc())
    ).all()
    items = [_duty_public(session, row) for row in rows]
    safe_page, safe_size = page_bounds(page, page_size, default_size=10)
    sliced, total = slice_page(items, safe_page, safe_size)
    return {"items": sliced, "total": total, "page": safe_page, "page_size": safe_size}


def shift_log(
    session: Session,
    user: User,
    date_from: str | None,
    date_to: str | None,
    status: str | None,
    page: int | None = None,
    page_size: int | None = None,
) -> dict:
    from core.pagination import page_bounds, slice_page

    statement = select(ShiftSession).where(ShiftSession.station_id == user.station_id)
    if date_from:
        statement = statement.where(ShiftSession.business_date >= _parse_date(date_from))
    if date_to:
        statement = statement.where(ShiftSession.business_date <= _parse_date(date_to))
    if status:
        statement = statement.where(ShiftSession.status == status)
    rows = session.exec(statement.order_by(ShiftSession.business_date.desc(), ShiftSession.starts_at.desc())).all()
    items = [_log_row(session, row) for row in rows]
    safe_page, safe_size = page_bounds(page, page_size, default_size=10)
    sliced, total = slice_page(items, safe_page, safe_size)
    return {"items": sliced, "total": total, "page": safe_page, "page_size": safe_size}


def duty_entries(session: Session, shift: ShiftSession) -> list[dict]:
    duties = session.exec(select(ShiftDuty).where(ShiftDuty.session_id == shift.id)).all()
    entries = []
    for duty in duties:
        liters = Decimal("0")
        for reading in _readings(session, duty.id):
            if reading.liters is not None:
                liters += q_liters(reading.liters)
        entries.append(
            {
                "status": duty.status,
                "liters": liters,
                "expected_cash": duty.expected_cash or 0,
                "variance": duty.variance or 0,
            }
        )
    return entries


def _log_row(session: Session, shift: ShiftSession) -> dict:
    entries = duty_entries(session, shift)
    totals = rollup(entries)
    duties = session.exec(select(ShiftDuty).where(ShiftDuty.session_id == shift.id)).all()
    template = session.get(ShiftTemplate, shift.template_id)
    supervisor = _supervisor_name(session, shift, duties)
    has_approved = totals["duties"] > 0
    return {
        "id": str(shift.id),
        "code": shift.code,
        "business_date": shift.business_date.isoformat(),
        "window": _window(template),
        "template_name": template.name_ar if template else "",
        "supervisor": supervisor,
        "status": shift.status,
        "status_label": _SESSION_LABELS.get(shift.status, shift.status),
        "liters": format_liters(totals["liters"]) if has_approved else None,
        "revenue": format_money(totals["revenue"]) if has_approved else None,
        "variance": format_money(totals["variance"]) if has_approved else None,
        "variance_label": variance_label(totals["variance"]) if has_approved else None,
        "operators": _operator_summary(session, duties),
    }


def _supervisor_name(session: Session, shift: ShiftSession, duties: list[ShiftDuty]) -> str:
    if shift.supervisor_id:
        person = session.get(User, shift.supervisor_id)
        if person is not None:
            return person.full_name
    approvers = [duty.approved_by for duty in duties if duty.approved_by]
    if approvers:
        person = session.get(User, approvers[-1])
        if person is not None:
            return person.full_name
    return ""


def _window(template: ShiftTemplate | None) -> str:
    if template is None:
        return ""
    start = template.starts_at
    end = template.ends_at
    return f"{template.name_ar} {start.hour:02d}:{start.minute:02d}–{end.hour:02d}:{end.minute:02d}"


def _maybe_close_session(session: Session, session_id: uuid.UUID) -> None:
    shift = session.get(ShiftSession, session_id)
    if shift is None or shift.status == "approved":
        return
    duties = session.exec(select(ShiftDuty).where(ShiftDuty.session_id == shift.id)).all()
    if any(duty.status != "approved" for duty in duties):
        return
    attendances = session.exec(select(Attendance).where(Attendance.session_id == shift.id)).all()
    covered = {duty.user_id for duty in duties}
    for row in attendances:
        if row.status in {"present", "late", "assigned", "completed"} and row.user_id not in covered:
            return
    shift.status = "approved"
    shift.updated_at = utcnow()
    session.add(shift)


def _stored_figures(duty: ShiftDuty, readings: list[ShiftReading]) -> dict:
    lines = [
        {
            "nozzle_id": str(row.nozzle_id),
            "opening": row.opening_meter,
            "closing": row.closing_meter,
            "unit_price": row.unit_price,
            "rollover": row.rollover,
            "rollover_at": row.rollover_at,
        }
        for row in readings
    ]
    return reconcile(lines, duty.cash_handed or 0)


def _figures_match(duty: ShiftDuty, figures: dict) -> bool:
    return (
        q_money(duty.expected_cash or 0) == figures["expected_cash"]
        and q_money(duty.variance or 0) == figures["variance"]
        and q_money(duty.cash_handed or 0) == figures["cash_handed"]
        and format_liters(sum((row["liters"] for row in figures["lines"]), Decimal("0")))
        == format_liters(figures["liters"])
    )


def _notify_approvers(session: Session, actor: User, duty: ShiftDuty) -> None:
    permission = session.exec(select(Permission).where(Permission.code == "shifts.approve")).first()
    if permission is None:
        return
    role_ids = session.exec(
        select(RolePermission.role_id).where(RolePermission.permission_id == permission.id)
    ).all()
    if not role_ids:
        return
    people = session.exec(
        select(User).where(
            User.station_id == actor.station_id,
            User.is_active == True,  # noqa: E712
            User.role_id.in_(role_ids),  # type: ignore[attr-defined]
        )
    ).all()
    for person in people:
        session.add(
            Notification(
                station_id=actor.station_id,
                user_id=person.id,
                kind="duty_pending",
                title="وردية بانتظار التوقيع",
                body="أغلق موظف ورديته وهي بانتظار اعتماد المشرف.",
                entity_type="shift_duty",
                entity_id=str(duty.id),
            )
        )


def _close_public(session: Session, duty: ShiftDuty, figures: dict) -> dict:
    body = _duty_public(session, duty)
    body.update(
        {
            "liters": format_liters(figures["liters"]),
            "expected_cash": format_money(figures["expected_cash"]),
            "cash_handed": format_money(figures["cash_handed"]),
            "variance": format_money(figures["variance"]),
            "variance_kind": figures["variance_kind"],
            "variance_label": variance_label(figures["variance"]),
            "lines": [
                {
                    "nozzle_id": line["nozzle_id"],
                    "liters": format_liters(line["liters"]),
                    "unit_price": format_price(line["unit_price"]),
                    "line_amount": format_money(line["line_amount"]),
                }
                for line in figures["lines"]
            ],
        }
    )
    return body


def _duty_public(session: Session, duty: ShiftDuty) -> dict:
    employee = session.get(User, duty.user_id)
    approver = session.get(User, duty.approved_by) if duty.approved_by else None
    shift = session.get(ShiftSession, duty.session_id)
    readings = _readings(session, duty.id)
    liters = Decimal("0")
    lines = []
    for reading in readings:
        if reading.liters is not None:
            liters += q_liters(reading.liters)
        nozzle, pump = _nozzle_pump(session, reading.nozzle_id)
        tank = session.get(Tank, pump.tank_id)
        product = session.get(FuelProduct, tank.product_id) if tank else None
        lines.append(
            {
                "nozzle_id": str(reading.nozzle_id),
                "nozzle_code": nozzle.code,
                "label": nozzle.label,
                "pump_code": pump.code,
                "product_name": product.name_ar if product else "",
                "opening_meter": format_liters(reading.opening_meter),
                "closing_meter": format_liters(reading.closing_meter) if reading.closing_meter is not None else None,
                "liters": format_liters(reading.liters) if reading.liters is not None else None,
                "unit_price": format_price(reading.unit_price),
                "line_amount": format_money(reading.line_amount) if reading.line_amount is not None else None,
            }
        )
    kind = None
    if duty.variance is not None:
        from shifts.reconciliation import variance_kind

        kind = variance_kind(q_money(duty.variance))
    template = session.get(ShiftTemplate, shift.template_id) if shift else None
    tz = _station_tz(session, duty.station_id)
    closed_at = duty.submitted_at or duty.approved_at
    return {
        "id": str(duty.id),
        "session_id": str(duty.session_id),
        "session_code": shift.code if shift else "",
        "template_name": template.name_ar if template else "",
        "business_date": shift.business_date.isoformat() if shift else "",
        "user_id": str(duty.user_id),
        "full_name": employee.full_name if employee else "",
        "employee_code": employee.employee_code if employee else "",
        "rostered_name": _rostered_name(session, duty),
        "taken_over": bool(_rostered_name(session, duty)),
        "status": duty.status,
        "status_label": _STATUS_LABELS.get(duty.status, duty.status),
        "opened_at": _iso(as_utc(duty.opened_at)),
        "submitted_at": _iso(as_utc(duty.submitted_at)),
        "approved_at": _iso(as_utc(duty.approved_at)),
        "opened_at_label": _local_clock(duty.opened_at, tz),
        "closed_at_label": _local_clock(closed_at, tz),
        "work_hours_label": _work_hours_label(duty.opened_at, closed_at, tz),
        "approved_by_name": approver.full_name if approver else None,
        "reject_reason": duty.reject_reason,
        "liters": format_liters(liters) if duty.status != "open" else None,
        "expected_cash": format_money(duty.expected_cash) if duty.expected_cash is not None else None,
        "cash_handed": format_money(duty.cash_handed) if duty.cash_handed is not None else None,
        "variance": format_money(duty.variance) if duty.variance is not None else None,
        "variance_kind": kind,
        "variance_label": variance_label(duty.variance) if duty.variance is not None else None,
        "lines": lines,
    }


def _assigned_nozzles(session: Session, attendance: Attendance) -> list[dict]:
    rows = []
    for link in _assignments(session, attendance):
        nozzle, pump = _nozzle_pump(session, link.nozzle_id)
        tank = session.get(Tank, pump.tank_id)
        product = session.get(FuelProduct, tank.product_id) if tank else None
        price = None
        block = None
        selectable = True
        if tank is not None:
            try:
                price = _price_for_nozzle(session, nozzle)
            except AppError:
                price = None
                block = "لا يوجد سعر ساري لهذا المنتج."
                selectable = False
        if pump.status == "maintenance":
            block = "المضخة في الصيانة ولا يمكن فتح وردية عليها."
            selectable = False
        elif nozzle.status != "ready":
            block = "المسدس غير جاهز للتشغيل."
            selectable = False
        rows.append(
            {
                "nozzle_id": str(nozzle.id),
                "code": nozzle.code,
                "label": nozzle.label,
                "pump_code": pump.code,
                "pump_status": pump.status,
                "product_name": product.name_ar if product else "",
                "current_meter": format_liters(nozzle.current_meter),
                "unit_price": format_price(price.price_per_liter) if price else None,
                "status": nozzle.status,
                "selectable": selectable,
                "block_reason": block,
            }
        )
    return rows


def _price_for_nozzle(session: Session, nozzle: Nozzle) -> FuelPrice:
    pump = session.get(Pump, nozzle.pump_id)
    tank = session.get(Tank, pump.tank_id) if pump else None
    if tank is None:
        raise AppError("PRICE_MISSING", "لا يوجد سعر ساري لهذا المنتج.", 422)
    moment = utcnow()
    rows = session.exec(
        select(FuelPrice)
        .where(FuelPrice.product_id == tank.product_id)
        .order_by(FuelPrice.effective_from.desc(), FuelPrice.created_at.desc())
    ).all()
    for row in rows:
        effective = as_utc(row.effective_from)
        if effective is not None and effective <= moment:
            return row
    raise AppError("PRICE_MISSING", "لا يوجد سعر ساري لهذا المنتج.", 422)


def _ensure_free(session: Session, nozzle_id: uuid.UUID) -> None:
    duties = session.exec(
        select(ShiftDuty).where(ShiftDuty.status.in_(["open", "pending_approval"]))  # type: ignore[attr-defined]
    ).all()
    busy_ids = [duty.id for duty in duties]
    if not busy_ids:
        return
    held = session.exec(
        select(ShiftReading).where(
            ShiftReading.nozzle_id == nozzle_id,
            ShiftReading.duty_id.in_(busy_ids),  # type: ignore[attr-defined]
        )
    ).first()
    if held is not None:
        raise AppError("NOZZLE_BUSY", "هذا المسدس مرتبط بوردية لم تُعتمد بعد.", 409)


def _pick_attendance(session: Session, user: User, today):
    rows = session.exec(
        select(Attendance, ShiftSession)
        .join(ShiftSession, ShiftSession.id == Attendance.session_id)
        .where(Attendance.user_id == user.id, ShiftSession.business_date == today)
        .order_by(ShiftSession.starts_at)
    ).all()
    if not rows:
        return None, None
    now = utcnow()
    for attendance, shift in rows:
        duty = _duty_for(session, shift.id, user.id)
        if duty is not None and duty.status in {"open", "rejected", "pending_approval"}:
            return attendance, shift
    for attendance, shift in rows:
        start = as_utc(shift.starts_at)
        end = as_utc(shift.ends_at)
        if start and end and start <= now <= end:
            return attendance, shift
    for attendance, shift in rows:
        if attendance.status in _OPEN_STATUSES:
            return attendance, shift
    return rows[-1]


def _empty(today, reason: str, shift: ShiftSession | None = None) -> dict:
    return {
        "date": today.isoformat(),
        "can_open": False,
        "self_service": False,
        "reason": reason,
        "session": None,
        "shifts": [],
        "identity": None,
        "attendance_status": None,
        "duty": None,
        "nozzles": [],
    }


def _identity(user: User) -> dict:
    return {
        "id": str(user.id),
        "full_name": user.full_name,
        "employee_code": user.employee_code,
    }


def _self_service(session: Session, user: User, today, identity: dict) -> dict:
    shifts = _operator_shifts(session, user, today)
    claimable = [item for item in shifts if item["claimable"]]
    nozzles = _station_nozzles(session, user)
    ready = [item for item in nozzles if item["selectable"]]
    reason = None
    if not claimable:
        reason = "لا توجد وردية متاحة للفتح الآن." if shifts else "لا توجد ورديات مجدولة لهذا اليوم."
    elif not ready:
        reason = "لا توجد مضخة جاهزة لفتح وردية عليها."
    return {
        "date": today.isoformat(),
        "can_open": bool(claimable) and bool(ready),
        "self_service": True,
        "reason": reason,
        "session": None,
        "shifts": shifts,
        "identity": identity,
        "attendance_status": None,
        "duty": None,
        "nozzles": nozzles,
    }


def _active_duty_today(session: Session, user: User, today):
    rows = session.exec(
        select(ShiftDuty, ShiftSession)
        .join(ShiftSession, ShiftSession.id == ShiftDuty.session_id)
        .where(
            ShiftDuty.user_id == user.id,
            ShiftSession.business_date == today,
            ShiftDuty.status.in_(["open", "pending_approval", "rejected"]),  # type: ignore[attr-defined]
        )
        .order_by(ShiftSession.starts_at)
    ).all()
    if not rows:
        return None, None
    return rows[0]


def _align_worker_assignments(session: Session, user: User, shift: ShiftSession, attendance: Attendance, payload):
    rostered_id = None
    rostered_names: list[str] = []
    requested: list[uuid.UUID] = []
    for item in payload.nozzles:
        nozzle_id = _uuid(item.nozzle_id, "المسدس غير معروف.")
        if nozzle_id in requested:
            raise AppError("NOZZLE_BUSY", "لا يمكن تكرار المسدس في الوردية نفسها.", 409)
        nozzle, pump = _nozzle_pump(session, nozzle_id)
        if nozzle.station_id != user.station_id:
            raise AppError("NOZZLE_NOT_FOUND", "تعذر العثور على المسدس.", 404)
        if pump.status == "maintenance":
            raise AppError("PUMP_UNAVAILABLE", "المضخة في الصيانة ولا يمكن فتح وردية عليها.", 409)
        if nozzle.status != "ready":
            raise AppError("NOZZLE_UNAVAILABLE", "المسدس غير جاهز للتشغيل.", 409)
        _ensure_free(session, nozzle.id)
        requested.append(nozzle_id)
    current = {row.nozzle_id: row for row in _assignments(session, attendance)}
    for nozzle_id, row in list(current.items()):
        if nozzle_id not in requested:
            session.delete(row)
            session.flush()
    for nozzle_id in requested:
        if nozzle_id in current:
            continue
        taken = session.exec(
            select(ShiftAssignment).where(
                ShiftAssignment.session_id == shift.id,
                ShiftAssignment.nozzle_id == nozzle_id,
            )
        ).first()
        if taken is not None:
            previous = session.get(Attendance, taken.attendance_id)
            if previous is not None and previous.user_id != user.id:
                person = session.get(User, previous.user_id)
                if person is not None:
                    rostered_names.append(person.full_name)
                    if rostered_id is None:
                        rostered_id = person.id
                previous.note = f"نُقل التكليف إلى {user.full_name}"
                previous.updated_at = utcnow()
                session.add(previous)
            session.delete(taken)
            session.flush()
        session.add(
            ShiftAssignment(
                station_id=shift.station_id,
                session_id=shift.id,
                attendance_id=attendance.id,
                nozzle_id=nozzle_id,
            )
        )
    if rostered_names:
        attendance.note = f"استلم الوردية بدل {'، '.join(rostered_names)}"
        attendance.updated_at = utcnow()
        session.add(attendance)
    return rostered_id


def _session_block_reason(session: Session, shift: ShiftSession | None, template: ShiftTemplate) -> str | None:
    if not template.is_active:
        return "هذه الوردية متوقفة في إعدادات المحطة."
    if shift is None:
        return None
    if shift.status == "cancelled":
        return "معطّلة لهذا اليوم من قبل مدير المحطة."
    if shift.status == "approved":
        return "تم إغلاق الوردية واعتماد جميع العهد."
    if shift.status == "closed":
        return "انتهت مدة الوردية."
    ends = as_utc(shift.ends_at)
    if ends is not None and ends < utcnow():
        return "انتهت مدة الوردية."
    return None


def _operator_shifts(session: Session, user: User, today) -> list[dict]:
    from stations.shift_timing import today_plannable_templates

    templates = today_plannable_templates(session, user.station_id)
    rows = []
    for template in templates:
        shift = session.exec(
            select(ShiftSession).where(
                ShiftSession.station_id == user.station_id,
                ShiftSession.template_id == template.id,
                ShiftSession.business_date == today,
            )
        ).first()
        block_reason = _session_block_reason(session, shift, template)
        rostered = _rostered_names(session, shift) if shift is not None else []
        session_status = shift.status if shift is not None else ("inactive" if not template.is_active else None)
        if session_status is None:
            status_label = "متاحة للفتح"
        elif session_status == "inactive":
            status_label = "متوقفة"
        else:
            status_label = _SESSION_LABELS.get(session_status, session_status)
        rows.append(
            {
                "template_id": str(template.id),
                "template_name": template.name_ar,
                "session_id": str(shift.id) if shift is not None else None,
                "window": _window(template),
                "rostered_name": "، ".join(rostered) if rostered else None,
                "claimable": block_reason is None,
                "session_status": session_status,
                "status_label": status_label,
                "block_reason": block_reason,
            }
        )
    return rows


def _rostered_names(session: Session, shift: ShiftSession) -> list[str]:
    attendances = session.exec(select(Attendance).where(Attendance.session_id == shift.id)).all()
    names = []
    for row in attendances:
        if row.status == "absent":
            continue
        person = session.get(User, row.user_id)
        if person is not None:
            names.append(person.full_name)
    return names


def _station_nozzles(session: Session, user: User) -> list[dict]:
    nozzles = session.exec(select(Nozzle).where(Nozzle.station_id == user.station_id)).all()
    rows = []
    for nozzle in nozzles:
        pump = session.get(Pump, nozzle.pump_id)
        if pump is None:
            continue
        tank = session.get(Tank, pump.tank_id)
        product = session.get(FuelProduct, tank.product_id) if tank else None
        price = None
        block = None
        selectable = pump.status == "active" and nozzle.status == "ready"
        if pump.status != "active":
            block = "المضخة غير متاحة لهذه الوردية."
        elif nozzle.status != "ready":
            block = "المسدس غير جاهز للتشغيل."
        if tank is None or not tank.is_active:
            block = "الخزان المرتبط بهذا المسدس غير متاح."
            selectable = False
        try:
            _ensure_free(session, nozzle.id)
        except AppError as exc:
            block = exc.message
            selectable = False
        if selectable and tank is not None:
            try:
                price = _price_for_nozzle(session, nozzle)
            except AppError as exc:
                price = None
                block = exc.message
                selectable = False
        rows.append(
            {
                "nozzle_id": str(nozzle.id),
                "code": nozzle.code,
                "label": nozzle.label,
                "pump_code": pump.code,
                "pump_status": pump.status,
                "product_name": product.name_ar if product else "",
                "current_meter": format_liters(nozzle.current_meter),
                "unit_price": format_price(price.price_per_liter) if price else None,
                "status": nozzle.status,
                "selectable": selectable,
                "block_reason": block,
            }
        )
    return rows


def _resolve_shift(session: Session, user: User, payload) -> ShiftSession:
    raw_session = (getattr(payload, "session_id", None) or "").strip()
    raw_template = (getattr(payload, "template_id", None) or "").strip()
    if raw_session:
        shift = _session_row(session, user, raw_session)
        if shift.status == "approved":
            raise AppError("SESSION_CLOSED", "هذه الوردية مغلقة ولا يمكن فتحها.", 409)
        if shift.status == "cancelled":
            raise AppError("SESSION_CANCELLED", "هذه الوردية معطّلة لهذا اليوم.", 409)
        return shift
    if not raw_template:
        raise AppError("VALIDATION_ERROR", "اختر الوردية التي تريد فتحها.", 422)
    station = session.get(Station, user.station_id)
    tz = station_timezone(station.timezone if station else "Africa/Tripoli")
    today = datetime.now(tz).date().isoformat()
    from attendance.routes import SessionCreate
    from attendance.services import open_session

    opened = open_session(
        session,
        user,
        SessionCreate(template_id=raw_template, business_date=today),
    )
    return _session_row(session, user, opened["id"])


def _self_claim(session: Session, user: User, shift: ShiftSession, payload):
    if not payload.nozzles:
        raise AppError("NOZZLES_INCOMPLETE", "اختر مسدساً واحداً على الأقل لفتح الوردية.", 422)
    seen: set[uuid.UUID] = set()
    rostered_id = None
    rostered_names: list[str] = []
    prepared: list[uuid.UUID] = []
    for item in payload.nozzles:
        nozzle_id = _uuid(item.nozzle_id, "المسدس غير معروف.")
        if nozzle_id in seen:
            raise AppError("NOZZLE_BUSY", "لا يمكن تكرار المسدس في الوردية نفسها.", 409)
        seen.add(nozzle_id)
        nozzle, pump = _nozzle_pump(session, nozzle_id)
        if nozzle.station_id != user.station_id:
            raise AppError("NOZZLE_NOT_FOUND", "تعذر العثور على المسدس.", 404)
        if pump.status == "maintenance":
            raise AppError("PUMP_UNAVAILABLE", "المضخة في الصيانة ولا يمكن فتح وردية عليها.", 409)
        if nozzle.status != "ready":
            raise AppError("NOZZLE_UNAVAILABLE", "المسدس غير جاهز للتشغيل.", 409)
        _ensure_free(session, nozzle.id)
        taken = session.exec(
            select(ShiftAssignment).where(
                ShiftAssignment.session_id == shift.id,
                ShiftAssignment.nozzle_id == nozzle.id,
            )
        ).first()
        if taken is not None:
            previous = session.get(Attendance, taken.attendance_id)
            if previous is not None and previous.user_id != user.id:
                person = session.get(User, previous.user_id)
                if person is not None:
                    rostered_names.append(person.full_name)
                    if rostered_id is None:
                        rostered_id = person.id
                previous.note = f"نُقل التكليف إلى {user.full_name}"
                previous.updated_at = utcnow()
                session.add(previous)
            session.delete(taken)
            session.flush()
        prepared.append(nozzle.id)
    note = f"استلم الوردية بدل {'، '.join(rostered_names)}" if rostered_names else "فتح الموظف الوردية بنفسه"
    attendance = Attendance(
        station_id=user.station_id,
        session_id=shift.id,
        user_id=user.id,
        recorded_by=user.id,
        status="present",
        note=note,
        check_in_at=utcnow(),
    )
    session.add(attendance)
    session.flush()
    for nozzle_id in prepared:
        session.add(
            ShiftAssignment(
                station_id=shift.station_id,
                session_id=shift.id,
                attendance_id=attendance.id,
                nozzle_id=nozzle_id,
            )
        )
    if rostered_names:
        session.add(
            Notification(
                station_id=user.station_id,
                kind="duty_takeover",
                title="استلام وردية",
                body=f"{user.full_name} فتح وردية كانت مرتبطة بـ {'، '.join(rostered_names)}.",
                entity_type="shift_session",
                entity_id=str(shift.id),
            )
        )
    write_audit(
        session,
        actor_id=user.id,
        action="duty_claimed",
        entity="shift_session",
        entity_id=str(shift.id),
        detail={"rostered": rostered_names or None},
    )
    return attendance, rostered_id


def _rostered_name(session: Session, duty: ShiftDuty) -> str | None:
    if duty.rostered_user_id is None or duty.rostered_user_id == duty.user_id:
        return None
    person = session.get(User, duty.rostered_user_id)
    return person.full_name if person is not None else None


def _operator_summary(session: Session, duties: list[ShiftDuty]) -> str:
    parts = []
    for duty in duties:
        employee = session.get(User, duty.user_id)
        if employee is None:
            continue
        rostered = _rostered_name(session, duty)
        if rostered:
            parts.append(f"{employee.full_name} بدل {rostered}")
        else:
            parts.append(employee.full_name)
    return "، ".join(parts)


def _session_brief(session: Session, shift: ShiftSession) -> dict:
    template = session.get(ShiftTemplate, shift.template_id)
    return {
        "id": str(shift.id),
        "code": shift.code,
        "template_name": template.name_ar if template else "",
        "status": shift.status,
        "status_label": _SESSION_LABELS.get(shift.status, shift.status),
        "starts_at": _iso(as_utc(shift.starts_at)),
        "ends_at": _iso(as_utc(shift.ends_at)),
    }


def _assignments(session: Session, attendance: Attendance) -> list[ShiftAssignment]:
    return session.exec(
        select(ShiftAssignment).where(ShiftAssignment.attendance_id == attendance.id)
    ).all()


def _duty_for(session: Session, session_id: uuid.UUID, user_id: uuid.UUID) -> ShiftDuty | None:
    return session.exec(
        select(ShiftDuty).where(ShiftDuty.session_id == session_id, ShiftDuty.user_id == user_id)
    ).first()


def _readings(session: Session, duty_id: uuid.UUID) -> list[ShiftReading]:
    return session.exec(select(ShiftReading).where(ShiftReading.duty_id == duty_id)).all()


def _duty(session: Session, user: User, duty_id: str) -> ShiftDuty:
    row = session.get(ShiftDuty, _uuid(duty_id, "تعذر العثور على الوردية."))
    if row is None or row.station_id != user.station_id:
        raise AppError("DUTY_NOT_FOUND", "تعذر العثور على الوردية.", 404)
    return row


def _session_row(session: Session, user: User, raw: str) -> ShiftSession:
    row = session.get(ShiftSession, _uuid(raw, "تعذر العثور على المناوبة."))
    if row is None or row.station_id != user.station_id:
        raise AppError("SESSION_NOT_FOUND", "تعذر العثور على المناوبة.", 404)
    return row


def _nozzle_pump(session: Session, nozzle_id: uuid.UUID) -> tuple[Nozzle, Pump]:
    nozzle = session.get(Nozzle, nozzle_id)
    pump = session.get(Pump, nozzle.pump_id) if nozzle else None
    if nozzle is None or pump is None:
        raise AppError("NOZZLE_NOT_FOUND", "تعذر العثور على المسدس.", 404)
    return nozzle, pump


def _lock_tank(session: Session, tank_id: uuid.UUID) -> Tank:
    statement = select(Tank).where(Tank.id == tank_id)
    bind = session.get_bind()
    if bind is not None and bind.dialect.name != "sqlite":
        statement = statement.with_for_update()
    tank = session.exec(statement).one()
    return tank


def _meter(raw: str) -> Decimal:
    try:
        value = q_liters(Decimal(str(raw).strip()))
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", "قراءة العداد غير صالحة.", 422) from exc
    if value < 0:
        raise AppError("VALIDATION_ERROR", "قراءة العداد لا تكون سالبة.", 422)
    return value


def _cash(raw: str) -> Decimal:
    try:
        value = q_money(Decimal(str(raw).strip()))
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", "المبلغ المسلم غير صالح.", 422) from exc
    if value < 0:
        raise AppError("VALIDATION_ERROR", "المبلغ المسلم لا يكون سالباً.", 422)
    return value


def _uuid(raw: str, message: str) -> uuid.UUID:
    try:
        return uuid.UUID(raw)
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", message, 422) from exc


def _parse_date(raw: str):
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة التاريخ يجب أن تكون سنة-شهر-يوم.", 422) from exc


def _iso(moment: datetime | None) -> str | None:
    if moment is None:
        return None
    return moment.astimezone(timezone.utc).isoformat()


def _station_tz(session: Session, station_id: uuid.UUID):
    station = session.get(Station, station_id)
    return station_timezone(station.timezone if station else "Africa/Tripoli")


def _local_clock(value: datetime | None, tz) -> str | None:
    if value is None:
        return None
    moment = as_utc(value)
    if moment is None:
        return None
    local = moment.astimezone(tz)
    return f"{local.hour:02d}:{local.minute:02d}"


def _work_hours_label(opened: datetime | None, closed: datetime | None, tz) -> str | None:
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
    if hours > 0:
        duration = f"{hours}س {minutes}د"
    else:
        duration = f"{minutes}د"
    return f"{start_text} – {end_text} · {duration}"
