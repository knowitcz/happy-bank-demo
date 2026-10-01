import logging

from fastapi import FastAPI
from fastapi.responses import FileResponse
from sqlmodel import SQLModel

from app.api.account_routes import router as account_router
from app.api.bank_routes import router as bank_router
from app.api.health_routes import router as health_router
from app.db import engine
from app.logging_config import setup_logging
from app.startup import create_default_accounts

# Setup logging first
setup_logging()
logger = logging.getLogger(__name__)

SQLModel.metadata.create_all(bind=engine)

app = FastAPI()

logger.info("Application starting up")

# Serve index.html from the static directory
@app.get("/")
def serve_static_files():
    return FileResponse("resources/static/index.html")

app.include_router(account_router, prefix="/api/v1", tags=["account"])
app.include_router(bank_router, prefix="/api/v1", tags=["bank"])
app.include_router(health_router, tags=["health"])

create_default_accounts()
