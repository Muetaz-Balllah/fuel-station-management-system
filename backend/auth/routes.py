from fastapi import APIRouter, Depends, File, Response, UploadFile
from sqlmodel import Session

from auth.schemas import (
    ChangePasswordRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    TokenResponse,
    UserPublic,
)
from auth.services import change_password, login, logout, refresh, to_public
from users.services import save_photo
from core.deps import get_current_user
from db import get_session
from users.models import User

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login_route(payload: LoginRequest, session: Session = Depends(get_session)) -> TokenResponse:
    return login(session, payload.username, payload.password, payload.remember_me)


@router.post("/refresh", response_model=TokenResponse)
def refresh_route(payload: RefreshRequest, session: Session = Depends(get_session)) -> TokenResponse:
    return refresh(session, payload.refresh_token)


@router.post("/logout", status_code=204)
def logout_route(payload: LogoutRequest, session: Session = Depends(get_session)) -> Response:
    logout(session, payload.refresh_token)
    return Response(status_code=204)


@router.post("/me/photo", response_model=UserPublic)
def upload_my_photo(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> UserPublic:
    save_photo(session, user, user.id, file)
    session.refresh(user)
    return to_public(session, user)


@router.get("/me", response_model=UserPublic)
def me_route(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> UserPublic:
    return to_public(session, user)


@router.post("/change-password", status_code=204)
def change_password_route(
    payload: ChangePasswordRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Response:
    change_password(session, user, payload.current_password, payload.new_password)
    return Response(status_code=204)
