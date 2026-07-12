from datetime import datetime, timezone

from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import check_password_hash, generate_password_hash

db = SQLAlchemy()


def _utcnow():
    """无时区 UTC 时间戳，规避 datetime.utcnow() 的弃用并保持 MySQL 存储一致。"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


# 安全防范：阻断对 MySQL 执行 drop_all 销毁数据的行为（沿用 ymjdns 约定）
_original_drop_all = db.drop_all


def safe_drop_all(*args, **kwargs):
    from flask import current_app

    if current_app:
        uri = current_app.config.get("SQLALCHEMY_DATABASE_URI", "")
        if "mysql" in str(uri).lower():
            raise RuntimeError(
                "【安全拦截】检测到连接为 MySQL 数据库，已阻断 drop_all() 以防销毁数据。"
            )
    _original_drop_all(*args, **kwargs)


db.drop_all = safe_drop_all


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False, index=True)
    email = db.Column(db.String(120), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=_utcnow)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def to_dict(self):
        return {
            "id": self.id,
            "username": self.username,
            "email": self.email,
            "created_at": self.created_at.strftime("%Y-%m-%d %H:%M:%S") if self.created_at else None,
        }


class EmailVerification(db.Model):
    __tablename__ = "email_verifications"

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), nullable=False, index=True)
    code = db.Column(db.String(6), nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    used = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=_utcnow)

    @property
    def is_expired(self):
        return _utcnow() > self.expires_at


class TokenBlacklist(db.Model):
    __tablename__ = "token_blacklist"

    id = db.Column(db.Integer, primary_key=True)
    jti = db.Column(db.String(64), unique=True, nullable=False, index=True)
    expires_at = db.Column(db.DateTime, nullable=False)
