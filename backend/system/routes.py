from fastapi import APIRouter, Depends
from sqlmodel import Session

from core.deps import get_current_user
from db import get_session
from system.clock import station_clock
from users.models import User

router = APIRouter(tags=["system"])


@router.get("/system/clock")
def read_clock(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict:
    return station_clock(session, user)
