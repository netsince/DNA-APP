import uuid
from datetime import datetime, timezone

from flask import current_app
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from app.models import TokenBlacklist, db


def _serializer():
    return URLSafeTimedSerializer(current_app.config["SECRET_KEY"], salt="dna-auth")


def issue_token(username: str) -> str:
    """签发带 jti 的 token，支持后续吊销。"""
    max_age = current_app.config.get("TOKEN_MAX_AGE", 86400)
    payload = {
        "sub": username,
        "jti": uuid.uuid4().hex,
        "exp": int(datetime.now(timezone.utc).timestamp()) + max_age,
    }
    return _serializer().dumps(payload)


def verify_token(token: str):
    """校验 token，已吊销或过期返回 None。"""
    try:
        data = _serializer().loads(token, max_age=current_app.config.get("TOKEN_MAX_AGE", 86400))
    except (BadSignature, SignatureExpired):
        return None
    jti = data.get("jti")
    if jti and TokenBlacklist.query.filter_by(jti=jti).first():
        return None
    return data.get("sub")


def revoke_token(token: str) -> None:
    """将 token 加入黑名单以实现登出/吊销。"""
    try:
        data = _serializer().loads(token, max_age=current_app.config.get("TOKEN_MAX_AGE", 86400))
    except (BadSignature, SignatureExpired):
        return
    jti = data.get("jti")
    if not jti:
        return
    exp = data.get("exp")
    expires_at = datetime.fromtimestamp(exp, tz=timezone.utc) if exp else datetime.now(timezone.utc)
    if not TokenBlacklist.query.filter_by(jti=jti).first():
        db.session.add(TokenBlacklist(jti=jti, expires_at=expires_at))
        db.session.commit()
