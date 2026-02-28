from app.routers.health import router as health_router
from app.routers.transactions import router as transactions_router
from app.routers.upload import router as upload_router
from app.routers.categories import router as categories_router
from app.routers.unified_transactions import router as unified_transactions_router
from app.routers.tags import router as tags_router
from app.routers.analytics import router as analytics_router
from app.routers.accounts import router as accounts_router
from app.routers.budgets import router as budgets_router
from app.routers.goals import router as goals_router
from app.routers.reminders import router as reminders_router
from app.routers.export import router as export_router

__all__ = [
    "health_router",
    "transactions_router",
    "upload_router",
    "categories_router",
    "unified_transactions_router",
    "tags_router",
    "analytics_router",
    "accounts_router",
    "budgets_router",
    "goals_router",
    "reminders_router",
    "export_router",
]
