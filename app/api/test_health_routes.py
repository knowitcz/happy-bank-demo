import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.dependencies import get_health_service
from app.api.health_routes import HEALTH_PATH, STATUS_OK, STATUS_UNAVAILABLE, router


class FakeHealthService:
    def __init__(self, ready: bool):
        self.ready = ready

    def is_database_ready(self) -> bool:
        return self.ready


@pytest.fixture
def make_client():
    app = FastAPI()
    app.include_router(router)

    def _make(ready: bool) -> TestClient:
        app.dependency_overrides[get_health_service] = lambda: FakeHealthService(ready)
        return TestClient(app)

    try:
        yield _make
    finally:
        app.dependency_overrides.clear()


def test_health_ok(make_client):
    response = make_client(True).get(HEALTH_PATH)
    assert response.status_code == 200
    assert response.json() == {"status": STATUS_OK}
    assert response.headers["content-type"].startswith("application/json")


def test_health_unavailable_when_db_not_ready(make_client):
    response = make_client(False).get(HEALTH_PATH)
    assert response.status_code == 503
    assert response.json() == {"status": STATUS_UNAVAILABLE}


def test_health_ignores_extra_query_params(make_client):
    response = make_client(True).get(HEALTH_PATH, params={"foo": "bar"})
    assert response.status_code == 200
    assert response.json() == {"status": STATUS_OK}


@pytest.mark.parametrize("method", ["post", "put", "delete", "patch"])
def test_health_rejects_non_get_methods(make_client, method):
    response = getattr(make_client(True), method)(HEALTH_PATH)
    assert response.status_code == 405
