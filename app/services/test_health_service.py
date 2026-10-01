from unittest.mock import Mock

import pytest
from sqlalchemy.exc import OperationalError, SQLAlchemyError

from app.services.health_service import HealthService


def test_database_ready_when_ping_succeeds():
    repo = Mock()
    assert HealthService(repo).is_database_ready() is True
    repo.ping.assert_called_once_with()


@pytest.mark.parametrize("error", [
    SQLAlchemyError("boom"),
    OperationalError("SELECT 1", {}, Exception("db down")),
])
def test_database_not_ready_when_ping_raises(error):
    repo = Mock()
    repo.ping.side_effect = error
    assert HealthService(repo).is_database_ready() is False
