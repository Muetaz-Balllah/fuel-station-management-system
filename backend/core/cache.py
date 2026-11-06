import json

import redis
from redis.exceptions import RedisError

from config import settings
from errors import AppError

_UNAVAILABLE = "تعذر الاتصال بخدمة الجلسات. تأكد أن Redis يعمل."


class SessionCache:
    """Allow-list of access-token ids. Logout and deactivation delete the key,
    so a still-unexpired JWT stops working. Swap the URL to a real Redis
    server; tests use redis_url=memory."""

    def __init__(self) -> None:
        self._client = None

    def _redis(self):
        if self._client is None:
            if settings.redis_url == "memory":
                import fakeredis

                self._client = fakeredis.FakeRedis(decode_responses=True)
            else:
                # Local Redis 3.0 does not understand HELLO. RESP2 works there and on Redis 6+.
                self._client = redis.Redis.from_url(
                    settings.redis_url, decode_responses=True, protocol=2
                )
        return self._client

    def ping(self) -> bool:
        try:
            return bool(self._redis().ping())
        except RedisError:
            return False

    def store(self, *, jti: str, user_id: str, role_code: str, permissions: list[str], ttl_seconds: int) -> None:
        payload = json.dumps(
            {"user_id": user_id, "role_code": role_code, "permissions": permissions},
            ensure_ascii=False,
        )
        try:
            client = self._redis()
            client.set(self._token_key(jti), payload, ex=ttl_seconds)
            client.sadd(self._user_key(user_id), jti)
            client.expire(
                self._user_key(user_id),
                settings.refresh_token_remember_days * 24 * 3600,
            )
        except RedisError as exc:
            raise AppError("REDIS_UNAVAILABLE", _UNAVAILABLE, 503) from exc

    def get(self, jti: str) -> dict | None:
        try:
            raw = self._redis().get(self._token_key(jti))
        except RedisError as exc:
            raise AppError("REDIS_UNAVAILABLE", _UNAVAILABLE, 503) from exc
        if not raw:
            return None
        data = json.loads(raw)
        data["permissions"] = list(data.get("permissions") or [])
        return data

    def revoke(self, jti: str) -> None:
        try:
            self._redis().delete(self._token_key(jti))
        except RedisError as exc:
            raise AppError("REDIS_UNAVAILABLE", _UNAVAILABLE, 503) from exc

    def revoke_user(self, user_id: str) -> None:
        try:
            client = self._redis()
            members = client.smembers(self._user_key(user_id))
            if members:
                client.delete(*[self._token_key(item) for item in members])
            client.delete(self._user_key(user_id))
        except RedisError as exc:
            raise AppError("REDIS_UNAVAILABLE", _UNAVAILABLE, 503) from exc

    @staticmethod
    def _token_key(jti: str) -> str:
        return f"jwt:{jti}"

    @staticmethod
    def _user_key(user_id: str) -> str:
        return f"user_jwt:{user_id}"


session_cache = SessionCache()
