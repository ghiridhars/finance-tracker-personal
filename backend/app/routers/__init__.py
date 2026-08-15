from app.routers.health import router as health_router
from app.routers.upload import router as upload_router
from app.routers.categories import router as categories_router
from app.routers.unified_transactions import router as unified_transactions_router
from app.routers.analytics import router as analytics_router
from app.routers.accounts import router as accounts_router
from app.routers.export import router as export_router
from app.routers.gdrive import router as gdrive_router
from app.routers.upi import router as upi_router
from app.routers.admin import router as admin_router
from app.routers.local_sync import router as local_sync_router
from app.routers.investment_rules import router as investment_rules_router
from app.routers.asset_classes import router as asset_classes_router
from app.routers.classification_rules import router as classification_rules_router
from app.routers.transfers import router as transfers_router

__all__ = [
    "health_router",
    "upload_router",
    "categories_router",
    "unified_transactions_router",
    "analytics_router",
    "accounts_router",
    "export_router",
    "gdrive_router",
    "upi_router",
    "admin_router",
    "local_sync_router",
    "investment_rules_router",
    "asset_classes_router",
    "classification_rules_router",
    "transfers_router",
]
