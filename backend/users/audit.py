import json
import uuid

from sqlmodel import Session

from users.models import AuditLog


def write_audit(
    session: Session,
    *,
    actor_id: uuid.UUID | None,
    action: str,
    entity: str,
    entity_id: str | None,
    detail: dict | None = None,
) -> None:
    session.add(
        AuditLog(
            actor_id=actor_id,
            action=action,
            entity=entity,
            entity_id=entity_id,
            detail=json.dumps(detail, ensure_ascii=False) if detail else None,
        )
    )
