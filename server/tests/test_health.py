import pytest

from app import create_app


@pytest.fixture
def client():
    app = create_app()
    return app.test_client()


def test_heartbeat_ok(client):
    resp = client.get("/api/heartbeat")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "ok"
    assert "time" in data
    assert "uptime" in data


def test_unknown_route_returns_json_404(client):
    resp = client.get("/api/does-not-exist")
    assert resp.status_code == 404
    assert resp.get_json()["error"] == "not_found"
