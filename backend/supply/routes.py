from fastapi import APIRouter, Depends, Query, File, UploadFile
from pydantic import BaseModel
from sqlmodel import Session

from core.deps import require_permission
from db import get_session
from supply.services import (
    cancel_order,
    create_order,
    create_supplier,
    get_supplier,
    list_orders,
    list_suppliers,
    receive_order,
    save_supplier_logo,
    summary,
    update_supplier,
)
from users.models import User

router = APIRouter(tags=["supply"])


class SupplierCreate(BaseModel):
    name: str
    headquarters: str = ""
    contact_name: str = ""
    phone: str = ""
    max_daily_liters: str


class SupplierUpdate(BaseModel):
    name: str | None = None
    headquarters: str | None = None
    contact_name: str | None = None
    phone: str | None = None
    max_daily_liters: str | None = None
    is_active: bool | None = None


class OrderCreate(BaseModel):
    supplier_id: str
    tank_id: str
    product_id: str
    ordered_liters: str
    expected_on: str
    notes: str | None = None


class ReceiveOrder(BaseModel):
    received_liters: str | None = None


@router.get("/suppliers")
def read_suppliers(
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_suppliers(session, user)
    return {"items": items, "total": len(items)}


@router.post("/suppliers", status_code=201)
def post_supplier(
    payload: SupplierCreate,
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return create_supplier(session, user, payload)


@router.get("/suppliers/{supplier_id}")
def read_supplier(
    supplier_id: str,
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return get_supplier(session, user, supplier_id)


@router.post("/suppliers/{supplier_id}/logo")
def upload_supplier_logo(
    supplier_id: str,
    file: UploadFile = File(...),
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return save_supplier_logo(session, user, supplier_id, file)


@router.patch("/suppliers/{supplier_id}")
def patch_supplier(
    supplier_id: str,
    payload: SupplierUpdate,
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return update_supplier(session, user, supplier_id, payload)


@router.get("/supply/summary")
def read_summary(
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return summary(session, user)


@router.get("/supply-orders")
def read_orders(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return list_orders(session, user, page=page, page_size=page_size)


@router.post("/supply-orders", status_code=201)
def post_order(
    payload: OrderCreate,
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return create_order(session, user, payload)


@router.post("/supply-orders/{order_id}/receive")
def post_receive(
    order_id: str,
    payload: ReceiveOrder | None = None,
    user: User = Depends(require_permission("supply.receive")),
    session: Session = Depends(get_session),
) -> dict:
    return receive_order(session, user, order_id, payload)


@router.post("/supply-orders/{order_id}/cancel")
def post_cancel(
    order_id: str,
    user: User = Depends(require_permission("supply.manage")),
    session: Session = Depends(get_session),
) -> dict:
    return cancel_order(session, user, order_id)
