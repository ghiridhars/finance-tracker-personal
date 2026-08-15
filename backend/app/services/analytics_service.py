"""
Analytics service — aggregate queries for dashboard & charts.

All methods operate on the unified_transactions table.
"""
import logging
from datetime import date, timedelta
from decimal import Decimal
from typing import Optional

from sqlalchemy import func, case
from sqlalchemy.orm import Session

from app.models.transaction import UnifiedTransaction
from app.models.category import Category
from app.models.enums import TransactionType

logger = logging.getLogger(__name__)


class AnalyticsService:
    """Aggregation queries for the dashboard."""

    @staticmethod
    def calculate_net_worth(db: Session) -> dict:
        """Calculate net worth from all active accounts."""
        from app.models.bank_account import BankAccount
        from app.models.statement_audit import StatementAudit
        from sqlalchemy import desc

        accounts = db.query(BankAccount).filter(BankAccount.is_active == True).all()

        bank_balances = Decimal('0.0')
        investment_value = Decimal('0.0')
        loan_outstanding = Decimal('0.0')
        credit_card_dues = Decimal('0.0')
        breakdown = []
        last_updated = None

        for account in accounts:
            balance = Decimal('0.0')
            acct_type = account.account_type
            acct_subtype = account.account_subtype

            if acct_type in ('SAVINGS', 'SALARY', 'CURRENT'):
                stmt = db.query(StatementAudit).filter(
                    StatementAudit.bank_account_id == account.id
                ).order_by(desc(StatementAudit.period_end)).first()
                if stmt and stmt.closing_balance:
                    balance = stmt.closing_balance
                    bank_balances += balance

            elif acct_type == 'CREDIT_CARD':
                stmt = db.query(StatementAudit).filter(
                    StatementAudit.bank_account_id == account.id
                ).order_by(desc(StatementAudit.period_end)).first()
                if stmt and stmt.closing_balance:
                    balance = -abs(stmt.closing_balance)
                    credit_card_dues += balance

            elif acct_type == 'LOAN' or (acct_subtype and acct_subtype.startswith('LOAN')):
                principal = account.loan_principal or Decimal('0.0')
                emi_sum_row = db.query(func.sum(UnifiedTransaction.amount)).filter(
                    UnifiedTransaction.bank_account_id == account.id,
                    UnifiedTransaction.type == TransactionType.DEBIT
                ).first()
                emi_sum = emi_sum_row[0] if emi_sum_row and emi_sum_row[0] else Decimal('0.0')
                balance = -(principal - emi_sum)
                if balance > 0:
                    balance = Decimal('0.0')
                loan_outstanding += balance

            elif acct_subtype in ('FD', 'MF', 'DEMAT', 'PPF', 'NPS'):
                val = account.current_value if account.current_value is not None else (account.invested_amount or Decimal('0.0'))
                balance = val
                investment_value += balance

            else:
                stmt = db.query(StatementAudit).filter(
                    StatementAudit.bank_account_id == account.id
                ).order_by(desc(StatementAudit.period_end)).first()
                if stmt and stmt.closing_balance:
                    balance = stmt.closing_balance
                    bank_balances += balance

            if balance != Decimal('0.0'):
                breakdown.append({
                    "id": account.id,
                    "name": account.name,
                    "bank": account.bank_name,
                    "type": acct_type,
                    "subtype": acct_subtype,
                    "balance": float(balance)
                })

            if account.value_updated_at:
                if not last_updated or account.value_updated_at > last_updated:
                    last_updated = account.value_updated_at

        latest_stmt = db.query(func.max(StatementAudit.period_end)).scalar()
        if latest_stmt:
            from datetime import datetime
            if isinstance(latest_stmt, datetime):
                stmt_dt = latest_stmt
            else:
                stmt_dt = datetime.combine(latest_stmt, datetime.min.time())
            
            if not last_updated or stmt_dt > last_updated:
                last_updated = stmt_dt

        net_worth = bank_balances + investment_value + loan_outstanding + credit_card_dues

        return {
            "bank_balances": float(bank_balances),
            "investment_value": float(investment_value),
            "loan_outstanding": float(loan_outstanding),
            "credit_card_dues": float(credit_card_dues),
            "net_worth": float(net_worth),
            "breakdown": breakdown,
            "last_updated": last_updated.isoformat() if last_updated else None
        }

    # ── Summary Cards ────────────────────────────────────────

    @staticmethod
    def get_summary(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> dict:
        """
        Returns a summary dict with:
          total_income, total_spending, net_savings,
          transaction_count, avg_transaction,
          top_category (by spending), active_banks
        """
        if not from_date:
            from_date = date.today() - timedelta(days=30)
        if not to_date:
            to_date = date.today()

        q = db.query(UnifiedTransaction).filter(
            UnifiedTransaction.date >= from_date,
            UnifiedTransaction.date <= to_date,
            UnifiedTransaction.is_transfer == False,
        )
        income = (
            q.filter(UnifiedTransaction.type == TransactionType.CREDIT)
            .with_entities(func.coalesce(func.sum(UnifiedTransaction.amount), 0))
            .scalar()
        )

        # Spending = sum of DEBIT amounts
        spending = (
            q.filter(UnifiedTransaction.type == TransactionType.DEBIT)
            .with_entities(func.coalesce(func.sum(UnifiedTransaction.amount), 0))
            .scalar()
        )

        tx_count = q.count()
        avg_tx = (
            q.with_entities(func.coalesce(func.avg(UnifiedTransaction.amount), 0))
            .scalar()
        )

        # Top spending category
        top_cat_row = (
            db.query(
                Category.name,
                func.sum(UnifiedTransaction.amount).label("total"),
            )
            .join(UnifiedTransaction, UnifiedTransaction.category_id == Category.id)
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
            )
            .group_by(Category.name)
            .order_by(func.sum(UnifiedTransaction.amount).desc())
            .first()
        )
        active_banks = (
            db.query(func.distinct(UnifiedTransaction.bank))
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.bank.isnot(None),
            )
            .count()
        )

        return {
            "from_date": from_date.isoformat(),
            "to_date": to_date.isoformat(),
            "total_income": float(income),
            "total_spending": float(spending),
            "net_savings": float(income) - float(spending),
            "transaction_count": tx_count,
            "avg_transaction": round(float(avg_tx), 2),
            "top_spending_category": top_cat_row[0] if top_cat_row else None,
            "top_spending_amount": float(top_cat_row[1]) if top_cat_row else 0,
            "active_banks": active_banks,
        }

    # ── Spending by Category ─────────────────────────────────

    @staticmethod
    def spending_by_category(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[dict]:
        """
        Returns list of {category, color, icon, amount, percentage, count}
        sorted by amount descending. Only DEBIT transactions.
        """
        if not from_date:
            from_date = date.today() - timedelta(days=30)
        if not to_date:
            to_date = date.today()

        rows = (
            db.query(
                Category.id,
                Category.name,
                Category.color,
                Category.icon,
                func.sum(UnifiedTransaction.amount).label("total"),
                func.count(UnifiedTransaction.id).label("count"),
            )
            .join(UnifiedTransaction, UnifiedTransaction.category_id == Category.id)
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
            )
            .group_by(Category.id, Category.name, Category.color, Category.icon)
            .order_by(func.sum(UnifiedTransaction.amount).desc())
            .all()
        )

        # Uncategorized debits
        uncategorized = (
            db.query(
                func.sum(UnifiedTransaction.amount).label("total"),
                func.count(UnifiedTransaction.id).label("count"),
            )
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.category_id.is_(None),
                UnifiedTransaction.is_transfer == False,
            )
            .first()
        )

        grand_total = sum(float(r.total) for r in rows)
        if uncategorized and uncategorized.total:
            grand_total += float(uncategorized.total)

        result = []
        for r in rows:
            amt = float(r.total)
            result.append({
                "category_id": r.id,
                "category": r.name,
                "color": r.color,
                "icon": r.icon,
                "amount": amt,
                "percentage": round(amt / grand_total * 100, 1) if grand_total > 0 else 0,
                "count": r.count,
            })

        if uncategorized and uncategorized.total and float(uncategorized.total) > 0:
            amt = float(uncategorized.total)
            result.append({
                "category_id": None,
                "category": "Uncategorized",
                "color": "#9E9E9E",
                "icon": "help_outline",
                "amount": amt,
                "percentage": round(amt / grand_total * 100, 1) if grand_total > 0 else 0,
                "count": uncategorized.count,
            })

        return result

    # ── Spending Trends (daily/weekly/monthly) ───────────────

    @staticmethod
    def spending_trends(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
        granularity: str = "daily",  # daily | weekly | monthly
    ) -> list[dict]:
        """
        Time-series spending data.
        Returns [{period, spending, income}].
        """
        if not from_date:
            from_date = date.today() - timedelta(days=30)
        if not to_date:
            to_date = date.today()

        base = db.query(UnifiedTransaction).filter(
            UnifiedTransaction.date >= from_date,
            UnifiedTransaction.date <= to_date,
            UnifiedTransaction.is_transfer == False,
        )

        if granularity == "monthly":
            period_expr = func.strftime("%Y-%m", UnifiedTransaction.date)
        elif granularity == "weekly":
            period_expr = func.strftime("%Y-W%W", UnifiedTransaction.date)
        else:
            period_expr = func.strftime("%Y-%m-%d", UnifiedTransaction.date)

        rows = (
            base.with_entities(
                period_expr.label("period"),
                func.sum(
                    case(
                        (UnifiedTransaction.type == TransactionType.DEBIT, UnifiedTransaction.amount),
                        else_=0,
                    )
                ).label("spending"),
                func.sum(
                    case(
                        (UnifiedTransaction.type == TransactionType.CREDIT, UnifiedTransaction.amount),
                        else_=0,
                    )
                ).label("income"),
                func.count(UnifiedTransaction.id).label("count"),
            )
            .group_by(period_expr)
            .order_by(period_expr)
            .all()
        )

        result = []
        for r in rows:
            entry: dict = {
                "period": r.period,
                "spending": float(r.spending),
                "income": float(r.income),
                "count": r.count,
            }
            # Per-bank breakdown for daily granularity (calendar heatmap)
            if granularity == "daily":
                bank_rows = (
                    base.filter(
                        period_expr == r.period,
                        UnifiedTransaction.type == TransactionType.DEBIT,
                    )
                    .with_entities(
                        func.coalesce(UnifiedTransaction.bank, "OTHER").label("bank"),
                        func.sum(UnifiedTransaction.amount).label("spending"),
                        func.count(UnifiedTransaction.id).label("count"),
                    )
                    .group_by(func.coalesce(UnifiedTransaction.bank, "OTHER"))
                    .all()
                )
                entry["by_account"] = [
                    {
                        "bank": br.bank,
                        "spending": float(br.spending),
                        "count": br.count,
                    }
                    for br in bank_rows
                ]
            result.append(entry)

        return result

    # ── Income vs Expense (monthly bar chart) ────────────────

    @staticmethod
    def income_vs_expense(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[dict]:
        """
        Monthly income vs expense breakdown.
        Returns [{month, income, expense, net}].
        """
        if not from_date:
            from_date = date.today() - timedelta(days=365)
        if not to_date:
            to_date = date.today()

        period_expr = func.strftime("%Y-%m", UnifiedTransaction.date)

        rows = (
            db.query(
                period_expr.label("month"),
                func.sum(
                    case(
                        (UnifiedTransaction.type == TransactionType.CREDIT, UnifiedTransaction.amount),
                        else_=0,
                    )
                ).label("income"),
                func.sum(
                    case(
                        (UnifiedTransaction.type == TransactionType.DEBIT, UnifiedTransaction.amount),
                        else_=0,
                    )
                ).label("expense"),
            )
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.is_transfer == False,
            )
            .group_by(period_expr)
            .order_by(period_expr)
            .all()
        )

        return [
            {
                "month": r.month,
                "income": float(r.income),
                "expense": float(r.expense),
                "net": float(r.income) - float(r.expense),
            }
            for r in rows
        ]

    # ── Month-over-Month Comparison ──────────────────────────

    @staticmethod
    def month_over_month(
        db: Session,
        *,
        ref_month: date | None = None,
    ) -> dict:
        """
        Compare current month vs previous month by category.
        Returns {current_month, previous_month, comparison: [{category, current, previous, change_pct}]}
        """
        if not ref_month:
            ref_month = date.today()

        # Current month boundaries
        curr_start = ref_month.replace(day=1)
        if curr_start.month == 12:
            curr_end = curr_start.replace(year=curr_start.year + 1, month=1, day=1) - timedelta(days=1)
        else:
            curr_end = curr_start.replace(month=curr_start.month + 1, day=1) - timedelta(days=1)

        # Previous month boundaries
        prev_end = curr_start - timedelta(days=1)
        prev_start = prev_end.replace(day=1)

        def _category_totals(start: date, end: date) -> dict[str, float]:
            rows = (
                db.query(
                    func.coalesce(Category.name, "Uncategorized").label("cat"),
                    func.sum(UnifiedTransaction.amount).label("total"),
                )
                .outerjoin(Category, UnifiedTransaction.category_id == Category.id)
                .filter(
                    UnifiedTransaction.date >= start,
                    UnifiedTransaction.date <= end,
                    UnifiedTransaction.type == TransactionType.DEBIT,
                    UnifiedTransaction.is_transfer == False,
                )
                .group_by(func.coalesce(Category.name, "Uncategorized"))
                .all()
            )
            return {r.cat: float(r.total) for r in rows}

        curr_totals = _category_totals(curr_start, curr_end)
        prev_totals = _category_totals(prev_start, prev_end)

        all_cats = sorted(set(curr_totals.keys()) | set(prev_totals.keys()))
        comparison = []
        for cat in all_cats:
            curr = curr_totals.get(cat, 0.0)
            prev = prev_totals.get(cat, 0.0)
            pct = round(((curr - prev) / prev * 100), 1) if prev > 0 else None
            comparison.append({
                "category": cat,
                "current": curr,
                "previous": prev,
                "change_pct": pct,
            })

        # Sort by absolute change descending
        comparison.sort(key=lambda x: abs(x["current"] - x["previous"]), reverse=True)

        curr_total = sum(curr_totals.values())
        prev_total = sum(prev_totals.values())

        return {
            "current_month": curr_start.strftime("%Y-%m"),
            "previous_month": prev_start.strftime("%Y-%m"),
            "current_total": curr_total,
            "previous_total": prev_total,
            "total_change_pct": (
                round(((curr_total - prev_total) / prev_total * 100), 1)
                if prev_total > 0 else None
            ),
            "comparison": comparison,
        }

    # ── Top Merchants ────────────────────────────────────────

    @staticmethod
    def top_merchants(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
        limit: int = 15,
    ) -> list[dict]:
        """
        Top merchants by spending amount.
        Returns [{merchant, amount, count, percentage}].
        """
        if not from_date:
            from_date = date.today() - timedelta(days=30)
        if not to_date:
            to_date = date.today()

        rows = (
            db.query(
                func.coalesce(UnifiedTransaction.merchant_name, UnifiedTransaction.description).label("merchant"),
                func.sum(UnifiedTransaction.amount).label("total"),
                func.count(UnifiedTransaction.id).label("count"),
            )
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
            )
            .group_by(
                func.coalesce(UnifiedTransaction.merchant_name, UnifiedTransaction.description)
            )
            .order_by(func.sum(UnifiedTransaction.amount).desc())
            .limit(limit)
            .all()
        )

        grand_total = sum(float(r.total) for r in rows)

        return [
            {
                "merchant": r.merchant,
                "amount": float(r.total),
                "count": r.count,
                "percentage": round(float(r.total) / grand_total * 100, 1) if grand_total > 0 else 0,
            }
            for r in rows
        ]

    # ── Bank-wise Split ──────────────────────────────────────

    @staticmethod
    def spending_by_bank(
        db: Session,
        *,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> list[dict]:
        """Spending grouped by bank."""
        if not from_date:
            from_date = date.today() - timedelta(days=30)
        if not to_date:
            to_date = date.today()

        rows = (
            db.query(
                func.coalesce(UnifiedTransaction.bank, "Unknown").label("bank"),
                func.sum(
                    case(
                        (UnifiedTransaction.type == TransactionType.DEBIT, UnifiedTransaction.amount),
                        else_=0,
                    )
                ).label("spending"),
                func.sum(
                    case(
                        (UnifiedTransaction.type == TransactionType.CREDIT, UnifiedTransaction.amount),
                        else_=0,
                    )
                ).label("income"),
                func.count(UnifiedTransaction.id).label("count"),
            )
            .filter(
                UnifiedTransaction.date >= from_date,
                UnifiedTransaction.date <= to_date,
                UnifiedTransaction.is_transfer == False,
            )
            .group_by(func.coalesce(UnifiedTransaction.bank, "Unknown"))
            .order_by(func.sum(UnifiedTransaction.amount).desc())
            .all()
        )

        return [
            {
                "bank": r.bank,
                "spending": float(r.spending),
                "income": float(r.income),
                "count": r.count,
            }
            for r in rows
        ]

    # ── Investment Analytics ─────────────────────────────────

    @staticmethod
    def get_investment_analytics(db: Session) -> dict:
        """
        Investment analytics.
        """
        # Filter conditions
        base_query = (
            db.query(UnifiedTransaction)
            .join(Category, UnifiedTransaction.category_id == Category.id)
            .filter(
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
                Category.name.in_(["Investment", "Insurance"])
            )
        )

        total_invested = (
            base_query.with_entities(func.coalesce(func.sum(UnifiedTransaction.amount), 0))
            .scalar()
        )
        total_invested = float(total_invested)

        # Rules
        from app.models.investment_rule import InvestmentRule
        from sqlalchemy.orm import joinedload
        rules = db.query(InvestmentRule).options(joinedload(InvestmentRule.asset_class)).all()

        txs = base_query.all()
        from collections import defaultdict
        platform_totals = defaultdict(float)
        asset_totals = defaultdict(float)
        asset_info = {}

        for tx in txs:
            raw_string = tx.merchant_name or tx.description or 'Unknown'
            resolved_platform = raw_string
            resolved_asset_class = None
            
            raw_string_lower = raw_string.lower()
            for rule in rules:
                if rule.keywords:
                    keywords = [k.strip().lower() for k in rule.keywords.split(',')]
                    if any(k and k in raw_string_lower for k in keywords):
                        resolved_platform = rule.platform_name
                        resolved_asset_class = rule.asset_class
                        break
            
            platform_totals[resolved_platform] += float(tx.amount)
            if resolved_asset_class:
                asset_totals[resolved_asset_class.id] += float(tx.amount)
                asset_info[resolved_asset_class.id] = resolved_asset_class
            else:
                asset_totals[0] += float(tx.amount)

        platforms = []
        for p, amt in sorted(platform_totals.items(), key=lambda x: x[1], reverse=True):
            platforms.append({
                "platform": p,
                "total_invested": amt,
                "percentage": round(amt / total_invested * 100, 1) if total_invested > 0 else 0
            })

        asset_classes = []
        for a_id, amt in sorted(asset_totals.items(), key=lambda x: x[1], reverse=True):
            if a_id == 0:
                asset_classes.append({
                    "asset_class": "Uncategorized",
                    "color": "#9E9E9E",
                    "icon": "help_outline",
                    "total_invested": amt,
                    "percentage": round(amt / total_invested * 100, 1) if total_invested > 0 else 0
                })
            else:
                ac = asset_info[a_id]
                asset_classes.append({
                    "asset_class": ac.name,
                    "color": ac.color_hex,
                    "icon": ac.icon_name,
                    "total_invested": amt,
                    "percentage": round(amt / total_invested * 100, 1) if total_invested > 0 else 0
                })

        # Trends
        period_expr = func.strftime("%Y-%m", UnifiedTransaction.date)
        trend_rows = (
            base_query.with_entities(
                period_expr.label("period"),
                func.sum(UnifiedTransaction.amount).label("amount")
            )
            .group_by(period_expr)
            .order_by(period_expr)
            .all()
        )

        trends = []
        for r in trend_rows:
            trends.append({
                "period": r.period,
                "amount": float(r.amount)
            })

        return {
            "total_invested": total_invested,
            "platforms": platforms,
            "asset_classes": asset_classes,
            "trends": trends
        }

    @staticmethod
    def get_unmapped_investments(db: Session) -> list[UnifiedTransaction]:
        base_query = (
            db.query(UnifiedTransaction)
            .join(Category, UnifiedTransaction.category_id == Category.id)
            .filter(
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
                Category.name.in_(["Investment", "Insurance"])
            )
        )
        txs = base_query.all()
        from app.models.investment_rule import InvestmentRule
        rules = db.query(InvestmentRule).all()
        
        unmapped = []
        for tx in txs:
            raw_string = tx.merchant_name or tx.description or 'Unknown'
            raw_string_lower = raw_string.lower()
            matched = False
            for rule in rules:
                if rule.keywords:
                    keywords = [k.strip().lower() for k in rule.keywords.split(',')]
                    if any(k and k in raw_string_lower for k in keywords):
                        matched = True
                        break
            if not matched:
                unmapped.append(tx)
                
        return unmapped

    @staticmethod
    def get_transactions_for_asset_class(db: Session, asset_class_name: str) -> list[UnifiedTransaction]:
        base_query = (
            db.query(UnifiedTransaction)
            .join(Category, UnifiedTransaction.category_id == Category.id)
            .filter(
                UnifiedTransaction.type == TransactionType.DEBIT,
                UnifiedTransaction.is_transfer == False,
                Category.name.in_(["Investment", "Insurance"]),
            )
            .order_by(UnifiedTransaction.date.desc())
        )
        txs = base_query.all()

        from app.models.investment_rule import InvestmentRule
        from sqlalchemy.orm import joinedload
        rules = db.query(InvestmentRule).options(joinedload(InvestmentRule.asset_class)).all()

        matching_txs = []
        for tx in txs:
            raw_string = tx.merchant_name or tx.description or 'Unknown'
            raw_string_lower = raw_string.lower()
            resolved_asset_name = "Uncategorized"
            for rule in rules:
                if rule.keywords:
                    keywords = [k.strip().lower() for k in rule.keywords.split(',')]
                    if any(k and k in raw_string_lower for k in keywords):
                        if rule.asset_class:
                            resolved_asset_name = rule.asset_class.name
                        break

            if resolved_asset_name.lower() == asset_class_name.lower():
                matching_txs.append(tx)

        return matching_txs

