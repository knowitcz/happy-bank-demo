import pytest
from sqlalchemy.exc import OperationalError
from sqlmodel import Session, create_engine

from app.repository.health_repository import HealthRepository


def test_ping_succeeds_on_in_memory_db():
    with Session(create_engine("sqlite://")) as session:
        assert HealthRepository(session).ping() is None


def test_ping_raises_when_database_unreachable(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'missing_dir' / 'x.db'}")
    with Session(engine) as session, pytest.raises(OperationalError):
        HealthRepository(session).ping()
