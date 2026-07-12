import smtplib
from email.mime.text import MIMEText

from flask import current_app


def send_verification_email(to_email: str, code: str) -> None:
    """通过 SMTP 发送邮箱验证码（STARTTLS）。"""
    cfg = current_app.config
    body = f"你的邮箱验证码是：{code}\n验证码 10 分钟内有效。"
    msg = MIMEText(body, _subtype="plain", _charset="utf-8")
    msg["Subject"] = "邮箱验证"
    msg["From"] = cfg.get("SMTP_FROM")
    msg["To"] = to_email

    with smtplib.SMTP(cfg.get("SMTP_SERVER"), cfg.get("SMTP_PORT"), timeout=10) as server:
        server.starttls()
        server.login(cfg.get("SMTP_USER"), cfg.get("SMTP_PASSWORD"))
        server.sendmail(cfg.get("SMTP_FROM"), [to_email], msg.as_string())
