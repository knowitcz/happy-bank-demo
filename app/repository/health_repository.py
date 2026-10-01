from sqlalchemy import text
from sqlmodel import Session


class HealthRepository:
    def __init__(self, session: Session):
        self.session = session

    def ping(self) -> None:
        """Run a trivial query; SQLAlchemyError propagates if the database is unreachable."""
        self.session.exec(text("SELECT 1"))
