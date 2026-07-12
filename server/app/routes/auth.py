import random
import re
from datetime import datetime, timedelta, timezone

from flask import Blueprint, current_app, jsonify, request

from app.models import EmailVerification, User, db
from app.utils.auth import issue_token, revoke_token, verify_token

auth_bp = Blueprint("auth", __name__)

USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,32}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _error(message, code):
    return jsonify(error=message), code


def _issue_code():
    return f"{random.randint(0, 999999):06d}"


def _store_code(email):
    code = _issue_code()
    expires_at = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(minutes=10)
    ev = EmailVerification(email=email, code=code, expires_at=expires_at)
    db.session.add(ev)
    db.session.commit()
    return code


def _send_email(email, code):
    from app.utils.mail import send_verification_email

    send_verification_email(email, code)


@auth_bp.post("/api/send-code")
def send_code():
    """下发邮箱验证码；注册前必须先调用，且注册时须提交正确验证码。"""
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()

    if not EMAIL_RE.match(email):
        return _error("邮箱格式不正确", 400)
    if User.query.filter_by(email=email).first():
        return _error("邮箱已注册", 409)

    code = _store_code(email)
    try:
        _send_email(email, code)
    except Exception:
        current_app.logger.exception("发送验证邮件失败")
        if not current_app.config.get("DEBUG"):
            return _error("邮件发送失败，请稍后重试", 502)

    resp = {"email": email}
    if current_app.config.get("DEBUG"):
        resp["dev_code"] = code  # 仅调试模式回显，便于本地验证
    return jsonify(resp), 200


@auth_bp.post("/api/register")
def register():
    """注册：必须携带正确且未过期的验证码，否则不创建账号。"""
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    code = (data.get("code") or "").strip()

    if not USERNAME_RE.match(username):
        return _error("用户名需为3-32位字母、数字或下划线", 400)
    if not EMAIL_RE.match(email):
        return _error("邮箱格式不正确", 400)
    min_len = current_app.config.get("PASSWORD_MIN_LENGTH", 8)
    if len(password) < min_len:
        return _error(f"密码至少{min_len}位", 400)
    if not code:
        return _error("验证码不能为空", 400)

    if User.query.filter_by(username=username).first():
        return _error("用户名已存在", 409)
    if User.query.filter_by(email=email).first():
        return _error("邮箱已注册", 409)

    ev = (
        EmailVerification.query.filter_by(email=email, code=code, used=False)
        .order_by(EmailVerification.id.desc())
        .first()
    )
    if not ev or ev.is_expired:
        return _error("验证码无效或已过期", 400)

    user = User(username=username, email=email)
    user.set_password(password)
    ev.used = True
    db.session.add(user)
    db.session.commit()
    return jsonify({"username": user.username, "email": user.email}), 201


@auth_bp.post("/api/login")
def login():
    data = request.get_json(silent=True) or {}
    account = (data.get("account") or "").strip().lower()
    password = data.get("password") or ""

    user = User.query.filter((User.username == account) | (User.email == account)).first()
    if not user or not user.check_password(password):
        return _error("账号或密码错误", 401)

    token = issue_token(user.username)
    return jsonify({"token": token, "username": user.username}), 200


@auth_bp.get("/api/me")
def me():
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        auth = auth[7:]
    username = verify_token(auth)
    if not username:
        return _error("未授权", 401)
    return jsonify({"username": username}), 200


@auth_bp.post("/api/logout")
def logout():
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        auth = auth[7:]
    if auth:
        revoke_token(auth)
    return jsonify({"ok": True}), 200
