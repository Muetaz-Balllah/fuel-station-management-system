import uuid
from datetime import datetime, time
from decimal import Decimal

from pydantic import BaseModel
from sqlmodel import Session, select

from errors import AppError
from stations.models import FuelPrice, FuelProduct, ShiftTemplate
from stations.windows import expand_window
from users.audit import write_audit
from users.models import User
from utils import as_utc, utcnow


class ProductPublic(BaseModel):
    id: str
    code: str
    name_ar: str
    is_active: bool
    sort_order: int
    active_price: str | None
    active_from: datetime | None


class ProductCreate(BaseModel):
    code: str
    name_ar: str
    price_per_liter: str | None = None


class PricePublic(BaseModel):
    id: str
    price_per_liter: str
    effective_from: datetime
    created_by: str | None


class PriceCreate(BaseModel):
    price_per_liter: str
    effective_from: datetime | None = None


class ShiftPublic(BaseModel):
    id: str
    name_ar: str
    starts_at: str
    ends_at: str
    grace_minutes: int
    is_active: bool
    crosses_midnight: bool


class ShiftWrite(BaseModel):
    name_ar: str
    starts_at: str
    ends_at: str
    grace_minutes: int = 10
    is_active: bool = True


class ShiftUpdate(BaseModel):
    name_ar: str | None = None
    starts_at: str | None = None
    ends_at: str | None = None
    grace_minutes: int | None = None
    is_active: bool | None = None


def list_products(session: Session, user: User) -> list[ProductPublic]:
    rows = session.exec(
        select(FuelProduct)
        .where(FuelProduct.station_id == user.station_id)
        .order_by(FuelProduct.sort_order, FuelProduct.code)
    ).all()
    return [_product_public(session, row) for row in rows]


def create_product(session: Session, user: User, payload: ProductCreate) -> ProductPublic:
    code = payload.code.strip().upper()
    name = payload.name_ar.strip()
    if not code or not name:
        raise AppError("VALIDATION_ERROR", "رمز المنتج واسمه مطلوبان.", 422)
    taken = session.exec(
        select(FuelProduct).where(
            FuelProduct.station_id == user.station_id,
            FuelProduct.code == code,
        )
    ).first()
    if taken is not None:
        raise AppError("DUPLICATE_PRODUCT", "رمز المنتج مستخدم بالفعل في هذه المحطة.", 409)
    current = session.exec(
        select(FuelProduct).where(FuelProduct.station_id == user.station_id)
    ).all()
    product = FuelProduct(
        station_id=user.station_id,
        code=code,
        name_ar=name,
        sort_order=len(current) + 1,
    )
    session.add(product)
    session.flush()
    if payload.price_per_liter:
        _add_price(session, user, product, payload.price_per_liter, None)
    write_audit(
        session,
        actor_id=user.id,
        action="product_created",
        entity="fuel_product",
        entity_id=str(product.id),
        detail={"code": code},
    )
    session.commit()
    session.refresh(product)
    return _product_public(session, product)


def list_prices(session: Session, user: User, product_id: uuid.UUID) -> list[PricePublic]:
    product = _product_for_station(session, user, product_id)
    rows = session.exec(
        select(FuelPrice)
        .where(FuelPrice.product_id == product.id)
        .order_by(FuelPrice.effective_from.desc(), FuelPrice.created_at.desc())
    ).all()
    return [_price_public(row) for row in rows]


def add_price(session: Session, user: User, product_id: uuid.UUID, payload: PriceCreate) -> PricePublic:
    product = _product_for_station(session, user, product_id)
    row = _add_price(session, user, product, payload.price_per_liter, payload.effective_from)
    write_audit(
        session,
        actor_id=user.id,
        action="price_added",
        entity="fuel_price",
        entity_id=str(row.id),
        detail={"product_id": str(product.id), "price_per_liter": _money(row.price_per_liter)},
    )
    session.commit()
    session.refresh(row)
    return _price_public(row)


def list_templates(session: Session, user: User) -> list[ShiftPublic]:
    rows = session.exec(
        select(ShiftTemplate)
        .where(ShiftTemplate.station_id == user.station_id)
        .order_by(ShiftTemplate.sort_order, ShiftTemplate.name_ar)
    ).all()
    return [_shift_public(row) for row in rows]


def create_template(session: Session, user: User, payload: ShiftWrite) -> ShiftPublic:
    name, starts, ends, grace = _shift_fields(
        payload.name_ar,
        payload.starts_at,
        payload.ends_at,
        payload.grace_minutes,
    )
    current = session.exec(
        select(ShiftTemplate).where(ShiftTemplate.station_id == user.station_id)
    ).all()
    row = ShiftTemplate(
        station_id=user.station_id,
        name_ar=name,
        starts_at=starts,
        ends_at=ends,
        grace_minutes=grace,
        is_active=payload.is_active,
        sort_order=len(current) + 1,
    )
    session.add(row)
    write_audit(
        session,
        actor_id=user.id,
        action="shift_template_created",
        entity="shift_template",
        entity_id=None,
        detail={"name_ar": name},
    )
    session.commit()
    session.refresh(row)
    return _shift_public(row)


def update_template(
    session: Session,
    user: User,
    template_id: uuid.UUID,
    payload: ShiftUpdate,
) -> ShiftPublic:
    row = session.get(ShiftTemplate, template_id)
    if row is None or row.station_id != user.station_id:
        raise AppError("TEMPLATE_NOT_FOUND", "تعذر العثور على الوردية.", 404)
    data = payload.model_dump(exclude_unset=True)
    name = data["name_ar"] if "name_ar" in data and data["name_ar"] is not None else row.name_ar
    starts = data["starts_at"] if "starts_at" in data and data["starts_at"] is not None else _clock(row.starts_at)
    ends = data["ends_at"] if "ends_at" in data and data["ends_at"] is not None else _clock(row.ends_at)
    grace = data["grace_minutes"] if "grace_minutes" in data and data["grace_minutes"] is not None else row.grace_minutes
    row.name_ar, row.starts_at, row.ends_at, row.grace_minutes = _shift_fields(name, starts, ends, grace)
    if "is_active" in data and data["is_active"] is not None:
        row.is_active = data["is_active"]
    row.updated_at = utcnow()
    session.add(row)
    write_audit(
        session,
        actor_id=user.id,
        action="shift_template_updated",
        entity="shift_template",
        entity_id=str(row.id),
        detail=None,
    )
    session.commit()
    session.refresh(row)
    return _shift_public(row)


def delete_template(session: Session, user: User, template_id: uuid.UUID) -> None:
    row = session.get(ShiftTemplate, template_id)
    if row is None or row.station_id != user.station_id:
        raise AppError("TEMPLATE_NOT_FOUND", "تعذر العثور على الوردية.", 404)
    from attendance.models import ShiftSession

    linked = session.exec(select(ShiftSession).where(ShiftSession.template_id == row.id)).first()
    if linked is not None:
        raise AppError(
            "TEMPLATE_IN_USE",
            "لا يمكن حذف وردية لها جلسات مسجّلة. عطّلها من جدول التفعيل أو أفرغ السجل أولاً.",
            409,
        )
    write_audit(
        session,
        actor_id=user.id,
        action="shift_template_deleted",
        entity="shift_template",
        entity_id=str(row.id),
        detail={"name_ar": row.name_ar},
    )
    session.delete(row)
    session.commit()


def _add_price(
    session: Session,
    user: User,
    product: FuelProduct,
    raw_price: str,
    effective_from: datetime | None,
) -> FuelPrice:
    price = _parse_price(raw_price)
    moment = as_utc(effective_from) or utcnow()
    row = FuelPrice(
        product_id=product.id,
        price_per_liter=price,
        effective_from=moment,
        created_by=user.id,
    )
    session.add(row)
    session.flush()
    return row


def _product_for_station(session: Session, user: User, product_id: uuid.UUID) -> FuelProduct:
    product = session.get(FuelProduct, product_id)
    if product is None or product.station_id != user.station_id:
        raise AppError("PRODUCT_NOT_FOUND", "تعذر العثور على المنتج.", 404)
    return product


def _product_public(session: Session, product: FuelProduct) -> ProductPublic:
    active = _active_price(session, product.id)
    return ProductPublic(
        id=str(product.id),
        code=product.code,
        name_ar=product.name_ar,
        is_active=product.is_active,
        sort_order=product.sort_order,
        active_price=_money(active.price_per_liter) if active else None,
        active_from=as_utc(active.effective_from) if active else None,
    )


def _active_price(session: Session, product_id: uuid.UUID) -> FuelPrice | None:
    moment = utcnow()
    rows = session.exec(
        select(FuelPrice)
        .where(FuelPrice.product_id == product_id)
        .order_by(FuelPrice.effective_from.desc(), FuelPrice.created_at.desc())
    ).all()
    for row in rows:
        effective = as_utc(row.effective_from)
        if effective is not None and effective <= moment:
            return row
    return None


def _price_public(row: FuelPrice) -> PricePublic:
    return PricePublic(
        id=str(row.id),
        price_per_liter=_money(row.price_per_liter),
        effective_from=as_utc(row.effective_from) or utcnow(),
        created_by=str(row.created_by) if row.created_by else None,
    )


def _shift_public(row: ShiftTemplate) -> ShiftPublic:
    starts = _as_time(row.starts_at)
    ends = _as_time(row.ends_at)
    return ShiftPublic(
        id=str(row.id),
        name_ar=row.name_ar,
        starts_at=_clock(starts),
        ends_at=_clock(ends),
        grace_minutes=row.grace_minutes,
        is_active=row.is_active,
        crosses_midnight=ends <= starts,
    )


def _shift_fields(name: str, starts_raw: str, ends_raw: str, grace: int) -> tuple[str, time, time, int]:
    cleaned = name.strip()
    if not cleaned:
        raise AppError("VALIDATION_ERROR", "اسم الوردية مطلوب.", 422)
    if grace < 0 or grace > 120:
        raise AppError("VALIDATION_ERROR", "مهلة التأخير يجب أن تكون بين 0 و 120 دقيقة.", 422)
    return cleaned, _parse_hhmm(starts_raw), _parse_hhmm(ends_raw), grace


def _parse_hhmm(value: str) -> time:
    parts = value.strip().split(":")
    if len(parts) < 2:
        raise AppError("VALIDATION_ERROR", "صيغة الوقت يجب أن تكون ساعة:دقيقة.", 422)
    try:
        return time(int(parts[0]), int(parts[1]))
    except ValueError as exc:
        raise AppError("VALIDATION_ERROR", "صيغة الوقت يجب أن تكون ساعة:دقيقة.", 422) from exc


def _parse_price(raw: str) -> Decimal:
    try:
        price = Decimal(raw.strip())
    except Exception as exc:
        raise AppError("VALIDATION_ERROR", "سعر اللتر غير صالح.", 422) from exc
    if price <= 0:
        raise AppError("VALIDATION_ERROR", "سعر اللتر يجب أن يكون أكبر من صفر.", 422)
    return price.quantize(Decimal("0.001"))


def _money(value: Decimal | float | str) -> str:
    return f"{Decimal(str(value)):.3f}"


def _clock(value: time) -> str:
    return f"{value.hour:02d}:{value.minute:02d}"


def _as_time(value: time | str) -> time:
    if isinstance(value, time):
        return value
    return _parse_hhmm(str(value))


def window_for(template: ShiftTemplate, business_date):
    """Used by later phases. Kept here so the overnight rule has one implementation."""
    return expand_window(_as_time(template.starts_at), _as_time(template.ends_at), business_date)
