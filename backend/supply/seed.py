from decimal import Decimal

from sqlmodel import Session, select

from stations.models import Station
from supply.models import Supplier

# Brega matches the supply mock. The other two names are on the mock's supplier
# list; their offices are filled in so the card has a headquarters and a contact.
_SEED = (
    ("شركة البريقة لتسويق النفط", "طريق المطار، طرابلس", "م. علي صالح", "021-3600000", Decimal("500000")),
    ("شركة ليبيا للنفط", "طرابلس", "مكتب المبيعات", "021-3600001", Decimal("300000")),
    ("شركة الراحلة للخدمات النفطية", "مصراتة", "قسم التوريد", "021-3600002", Decimal("200000")),
)


def seed_suppliers(session: Session, station: Station) -> None:
    existing = session.exec(select(Supplier).where(Supplier.station_id == station.id)).first()
    if existing is not None:
        return
    for name, headquarters, contact, phone, daily in _SEED:
        session.add(
            Supplier(
                station_id=station.id,
                name=name,
                headquarters=headquarters,
                contact_name=contact,
                phone=phone,
                max_daily_liters=daily,
                is_active=True,
            )
        )
