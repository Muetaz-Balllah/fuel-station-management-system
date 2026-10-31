import uuid

from fastapi import APIRouter, Depends
from sqlmodel import Session

from core.deps import require_permission
from db import get_session
from stations.catalog import (
    PriceCreate,
    PricePublic,
    ProductCreate,
    ProductPublic,
    ShiftPublic,
    ShiftUpdate,
    ShiftWrite,
    add_price,
    create_product,
    create_template,
    list_prices,
    list_products,
    list_templates,
    update_template,
)
from users.models import User

products_router = APIRouter(prefix="/products", tags=["products"])
templates_router = APIRouter(prefix="/shift-templates", tags=["shift-templates"])


@products_router.get("")
def read_products(
    user: User = Depends(require_permission("prices.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_products(session, user)
    return {"items": items, "total": len(items)}


@products_router.post("", response_model=ProductPublic, status_code=201)
def post_product(
    payload: ProductCreate,
    user: User = Depends(require_permission("prices.manage")),
    session: Session = Depends(get_session),
) -> ProductPublic:
    return create_product(session, user, payload)


@products_router.get("/{product_id}/prices")
def read_prices(
    product_id: uuid.UUID,
    user: User = Depends(require_permission("prices.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_prices(session, user, product_id)
    return {"items": items, "total": len(items)}


@products_router.post("/{product_id}/prices", response_model=PricePublic, status_code=201)
def post_price(
    product_id: uuid.UUID,
    payload: PriceCreate,
    user: User = Depends(require_permission("prices.manage")),
    session: Session = Depends(get_session),
) -> PricePublic:
    return add_price(session, user, product_id, payload)


@templates_router.get("")
def read_templates(
    user: User = Depends(require_permission("settings.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items = list_templates(session, user)
    return {"items": items, "total": len(items)}


@templates_router.post("", response_model=ShiftPublic, status_code=201)
def post_template(
    payload: ShiftWrite,
    user: User = Depends(require_permission("settings.manage")),
    session: Session = Depends(get_session),
) -> ShiftPublic:
    return create_template(session, user, payload)


@templates_router.patch("/{template_id}", response_model=ShiftPublic)
def patch_template(
    template_id: uuid.UUID,
    payload: ShiftUpdate,
    user: User = Depends(require_permission("settings.manage")),
    session: Session = Depends(get_session),
) -> ShiftPublic:
    return update_template(session, user, template_id, payload)
