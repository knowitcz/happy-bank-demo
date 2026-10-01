from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from app.api.dependencies import get_health_service
from app.services.health_service import HealthService

HEALTH_PATH = "/health"
STATUS_OK = "ok"
STATUS_UNAVAILABLE = "unavailable"

router = APIRouter()


@router.get(HEALTH_PATH)
def health(health_service: Annotated[HealthService, Depends(get_health_service)]) -> JSONResponse:
    """Liveness plus database readiness (SELECT 1 only)."""
    if health_service.is_database_ready():
        return JSONResponse({"status": STATUS_OK})
    return JSONResponse({"status": STATUS_UNAVAILABLE}, status_code=503)
