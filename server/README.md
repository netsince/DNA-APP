# dna-server

DNA 客户端配套后端，基于 Flask 工厂模式 + Flask-SQLAlchemy + Flask-Migrate（Alembic）。

## 开发

```bash
uv sync
cp .env.example .env   # 按需填写，SECRET_KEY 必须自行生成
uv run python main.py  # 或 uv run flask run
```

## 接口

- `GET /api/heartbeat` → `{"status":"ok","time":"...","uptime":<秒>}`
- `POST /api/send-code` `{email}` → 下发邮箱验证码（注册前必调）
- `POST /api/register` `{username,email,password,code}` → 必须携带正确且未过期的 `code`，否则不创建账号
- `POST /api/login` `{account,password}` → `token`
- `GET /api/me`（Bearer）→ 用户名
- `POST /api/logout`（Bearer）→ 吊销 token

> 注册强制校验邮箱验证码：未通过验证的邮箱不会生成任何账号。

## 数据库迁移

```bash
uv run flask db migrate -m "描述"   # 生成迁移脚本
uv run flask db upgrade             # 应用到数据库（改表前请先全量备份）
```

> 你正在操作的 MySQL 即生产库，任何改表/改数据前请先本地备份。

## 测试

```bash
uv run pytest
```
