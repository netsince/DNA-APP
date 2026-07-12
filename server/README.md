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
