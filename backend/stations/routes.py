from fastapi import APIRouter, Depends, File, UploadFile
from sqlmodel import Session

from core.deps import get_current_user, require_permission
from db import get_session
from stations.schemas import StationPublic, StationUpdate
from stations.services import get_for_user, save_logo, to_public, update_station
from users.models import User

router = APIRouter(prefix="/station", tags=["station"])


@router.get("", response_model=StationPublic)
def read_station(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> StationPublic:
    return to_public(get_for_user(session, user))


@router.patch("", response_model=StationPublic)
def patch_station(
    payload: StationUpdate,
    user: User = Depends(require_permission("settings.manage")),
    session: Session = Depends(get_session),
) -> StationPublic:
    return to_public(update_station(session, user, payload))


@router.post("/logo", response_model=StationPublic)
def upload_logo(
    file: UploadFile = File(...),
    user: User = Depends(require_permission("settings.manage")),
    session: Session = Depends(get_session),
) -> StationPublic:
    return to_public(save_logo(session, user, file))
