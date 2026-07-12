import pytest

from app import create_app
from app.config.settings import Config
from app.models import User, db


class TestConfig(Config):
    """测试配置：使用内存 SQLite，不触碰生产 MySQL。"""

    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    TESTING = True
    DEBUG = True


@pytest.fixture
def client():
    app = create_app(TestConfig)
    with app.app_context():
        db.create_all()
        yield app.test_client()
        db.session.remove()
        db.drop_all()


def test_send_code_returns_dev_code_in_debug(client):
    r = client.post("/api/send-code", json={"email": "a@example.com"})
    assert r.status_code == 200
    assert r.get_json()["dev_code"]


def test_register_requires_code(client):
    # 不传 code，注册必须被拒绝，且不创建账号
    r = client.post(
        "/api/register",
        json={"username": "alice", "email": "a@example.com", "password": "password123"},
    )
    assert r.status_code == 400
    assert User.query.count() == 0


def test_register_wrong_code_rejected(client):
    client.post("/api/send-code", json={"email": "a@example.com"})
    r = client.post(
        "/api/register",
        json={
            "username": "alice",
            "email": "a@example.com",
            "password": "password123",
            "code": "000000",
        },
    )
    assert r.status_code == 400
    assert User.query.count() == 0


def test_register_with_correct_code_creates_user_and_logs_in(client):
    r = client.post("/api/send-code", json={"email": "a@example.com"})
    code = r.get_json()["dev_code"]

    r = client.post(
        "/api/register",
        json={
            "username": "alice",
            "email": "a@example.com",
            "password": "password123",
            "code": code,
        },
    )
    assert r.status_code == 201
    assert User.query.count() == 1

    # 已注册邮箱不能再次发码
    r = client.post("/api/send-code", json={"email": "a@example.com"})
    assert r.status_code == 409

    # 登录可用
    r = client.post("/api/login", json={"account": "alice", "password": "password123"})
    assert r.status_code == 200
    assert "token" in r.get_json()


def test_register_duplicate_username_rejected(client):
    r = client.post("/api/send-code", json={"email": "a@example.com"})
    code = r.get_json()["dev_code"]
    client.post(
        "/api/register",
        json={
            "username": "alice",
            "email": "a@example.com",
            "password": "password123",
            "code": code,
        },
    )
    # 另一邮箱、相同用户名
    r = client.post("/api/send-code", json={"email": "b@example.com"})
    code2 = r.get_json()["dev_code"]
    r = client.post(
        "/api/register",
        json={
            "username": "alice",
            "email": "b@example.com",
            "password": "password123",
            "code": code2,
        },
    )
    assert r.status_code == 409
