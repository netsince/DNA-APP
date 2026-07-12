from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


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
