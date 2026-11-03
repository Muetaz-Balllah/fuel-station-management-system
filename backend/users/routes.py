import uuid

from fastapi import APIRouter, Depends, File, UploadFile
from sqlmodel import Session

from core.deps import require_permission
from db import get_session
from users.models import User
from users.schemas import PermissionReplace, RolePublic, StaffPublic, UserCreate, UserUpdate
from users.services import create_staff, list_roles, list_staff, replace_permissions, save_photo, update_staff

router = APIRouter(tags=["users"])


@router.get("/users")
def read_users(
    search: str | None = None,
    role: str = "all",
    limit: int = 20,
    offset: int = 0,
    user: User = Depends(require_permission("users.manage")),
    session: Session = Depends(get_session),
) -> dict:
    items, total = list_staff(session, user, search=search, role=role, limit=limit, offset=offset)
    return {"items": items, "total": total}


@router.post("/users", response_model=StaffPublic, status_code=201)
def post_user(
    payload: UserCreate,
    user: User = Depends(require_permission("users.manage")),
    session: Session = Depends(get_session),
) -> StaffPublic:
    return create_staff(session, user, payload)


@router.post("/users/{user_id}/photo", response_model=StaffPublic)
def upload_user_photo(
    user_id: uuid.UUID,
    file: UploadFile = File(...),
    user: User = Depends(require_permission("users.manage")),
    session: Session = Depends(get_session),
) -> StaffPublic:
    return save_photo(session, user, user_id, file)


@router.patch("/users/{user_id}", response_model=StaffPublic)
def patch_user(
    user_id: uuid.UUID,
    payload: UserUpdate,
    user: User = Depends(require_permission("users.manage")),
    session: Session = Depends(get_session),
) -> StaffPublic:
    return update_staff(session, user, user_id, payload)


@router.get("/roles")
def read_roles(
    user: User = Depends(require_permission("users.manage")),
    session: Session = Depends(get_session),
) -> dict:
    del user
    items = list_roles(session)
    return {"items": items, "total": len(items)}


@router.put("/roles/{role_id}/permissions", response_model=RolePublic)
def put_permissions(
    role_id: uuid.UUID,
    payload: PermissionReplace,
    user: User = Depends(require_permission("users.manage")),
    session: Session = Depends(get_session),
) -> RolePublic:
    return replace_permissions(session, user, role_id, payload)
