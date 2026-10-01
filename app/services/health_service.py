import logging

from sqlalchemy.exc import SQLAlchemyError

from app.repository.health_repository import HealthRepository

logger = logging.getLogger(__name__)


class HealthService:
    def __init__(self, repo: HealthRepository):
        self.repo = repo

    def is_database_ready(self) -> bool:
        try:
            self.repo.ping()
        except SQLAlchemyError:
            logger.warning("Database readiness check failed", exc_info=True)
            return False
        return True
