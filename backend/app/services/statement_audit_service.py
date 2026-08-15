"""
Statement audit service — the single save entry-point for parsed statements.

Replaces the old CreditCardStatementService and SavingsAccountStatementService.
Responsibilities:
  1. Record every parse attempt (success and failure) in the audit table.
  2. For successful imports: store statement-level metadata, resolve the bank
     account, delete old transactions on re-import, create unified transactions.
"""
import hashlib
import json
import logging
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.enums import StatementType, SourceType
from app.models.statement_audit import StatementAudit
from app.models.transaction import UnifiedTransaction

logger = logging.getLogger(__name__)


class StatementAuditService:
    """Create and query audit entries for statement import attempts."""

    # ── Record a parse attempt (success or failure) ──────────────

    @staticmethod
    def record(
        db: Session,
        *,
        file_name: str,
        file_content: bytes | None = None,
        file_size_bytes: int | None = None,
        bank_account_id: int | None = None,
        bank_name: str | None = None,
        statement_type: str,
        parser_strategy: str | None = None,
        transaction_count: int = 0,
        status: str,
        error_message: str | None = None,
        parse_trace: dict | str | None = None,
        source: str = "upload",
        # Statement metadata (nullable for failures)
        period_start=None,
        period_end=None,
        opening_balance=None,
        closing_balance=None,
        due_date=None,
        credit_limit=None,
        available_credit=None,
        minimum_amount_due=None,
        account_holder_name: str | None = None,
        card_holder_name: str | None = None,
        account_number: str | None = None,
        card_number: str | None = None,
        ifsc_code: str | None = None,
        branch_name: str | None = None,
    ) -> StatementAudit:
        """
        Create an audit entry.

        Parameters
        ----------
        status : str
            One of: SUCCESS, PARTIAL, FAILED, DUPLICATE, SKIPPED
        source : str
            One of: upload, local_sync, gdrive
        """
        file_hash = None
        if file_content is not None:
            file_hash = hashlib.sha256(file_content).hexdigest()
            if file_size_bytes is None:
                file_size_bytes = len(file_content)

        audit = StatementAudit(
            file_name=file_name,
            file_hash=file_hash,
            file_size_bytes=file_size_bytes,
            bank_account_id=bank_account_id,
            bank_name=bank_name,
            statement_type=statement_type,
            parser_strategy=parser_strategy,
            transaction_count=transaction_count,
            status=status,
            error_message=error_message,
            parse_trace=_serialize_parse_trace(parse_trace),
            source=source,
            # Statement metadata
            period_start=period_start,
            period_end=period_end,
            opening_balance=opening_balance,
            closing_balance=closing_balance,
            due_date=due_date,
            credit_limit=credit_limit,
            available_credit=available_credit,
            minimum_amount_due=minimum_amount_due,
            account_holder_name=account_holder_name,
            card_holder_name=card_holder_name,
            account_number=account_number,
            card_number=card_number,
            ifsc_code=ifsc_code,
            branch_name=branch_name,
        )
        db.add(audit)
        db.flush()
        return audit

    # ── Save a successfully-parsed statement (dedup + txns) ──────

    @staticmethod
    def save_statement(
        db: Session,
        dto,
        *,
        statement_type: StatementType,
        bank_account_id: int,
        bank_name: str,
        file_name: str,
        file_content: bytes | None = None,
        parser_strategy: str | None = None,
        parse_trace: dict | str | None = None,
        review_status: str = "AUTO_PARSED",
        review_reason: str | None = None,
        mismatched_indices: list[int] | None = None,
        source: str = "upload",
    ) -> StatementAudit:
        """
        Persist a parsed statement: upsert audit row, cascade-delete old
        unified transactions, and create fresh ones.

        Returns the (possibly updated) StatementAudit row.
        """
        from app.services.transaction_service import UnifiedTransactionService

        is_cc = statement_type == StatementType.CREDIT_CARD

        # Extract period dates from the DTO
        if is_cc:
            period_start = getattr(dto, "statement_date", None)
            period_end = getattr(dto, "statement_date", None)
        else:
            period_start = getattr(dto, "from_date", None)
            period_end = getattr(dto, "to_date", None)

        # ── Check for existing audit row (same account + period) ──
        existing: StatementAudit | None = None
        if bank_account_id and period_start is not None and period_end is not None:
            existing = (
                db.query(StatementAudit)
                .filter(
                    StatementAudit.bank_account_id == bank_account_id,
                    StatementAudit.period_start == period_start,
                    StatementAudit.period_end == period_end,
                    StatementAudit.status == "SUCCESS",
                )
                .first()
            )

        txns = getattr(dto, "transactions", [])
        txn_count = len(txns)

        if existing:
            logger.info(
                f"Re-importing statement audit id={existing.id} "
                f"({bank_name}/{statement_type.value} {period_start}–{period_end})"
            )
            # Delete old unified transactions linked to this audit
            db.query(UnifiedTransaction).filter(
                UnifiedTransaction.statement_audit_id == existing.id
            ).delete(synchronize_session="fetch")

            # Update metadata
            _apply_metadata(existing, dto, is_cc)
            existing.file_name = file_name
            existing.parser_strategy = parser_strategy
            existing.transaction_count = txn_count
            existing.parse_trace = _serialize_parse_trace(parse_trace)
            existing.imported_at = datetime.now(timezone.utc)
            if file_content is not None:
                existing.file_hash = hashlib.sha256(file_content).hexdigest()
                existing.file_size_bytes = len(file_content)
            db.flush()
            audit = existing
        else:
            # New audit row
            audit = StatementAuditService.record(
                db,
                file_name=file_name,
                file_content=file_content,
                bank_account_id=bank_account_id,
                bank_name=bank_name,
                statement_type=statement_type.value,
                parser_strategy=parser_strategy,
                transaction_count=txn_count,
                status="SUCCESS",
                parse_trace=parse_trace,
                source=source,
                period_start=period_start,
                period_end=period_end,
                opening_balance=getattr(dto, "opening_balance", None),
                closing_balance=_get_closing(dto, is_cc),
                due_date=getattr(dto, "due_date", None),
                credit_limit=getattr(dto, "credit_limit", None),
                available_credit=getattr(dto, "available_credit", None),
                minimum_amount_due=getattr(dto, "minimum_amount_due", None),
                account_holder_name=getattr(dto, "account_holder_name", None),
                card_holder_name=getattr(dto, "card_holder_name", None),
                account_number=getattr(dto, "account_number", None),
                card_number=getattr(dto, "card_number", None),
                ifsc_code=getattr(dto, "ifsc_code", None),
                branch_name=getattr(dto, "branch_name", None),
            )

        # Create unified transactions from parsed DTO
        source_type = SourceType.CREDIT_CARD if is_cc else SourceType.SAVINGS
        UnifiedTransactionService.create_from_parsed(
            db,
            dto=dto,
            statement_type=statement_type,
            source_type=source_type,
            statement_audit_id=audit.id,
            bank_name=bank_name,
            bank_account_id=bank_account_id,
            account_identifier=(
                getattr(dto, "card_number", None) if is_cc
                else getattr(dto, "account_number", None)
            ),
            review_status=review_status,
            review_reason=review_reason,
            mismatched_indices=mismatched_indices,
        )

        db.commit()
        db.refresh(audit)
        logger.info(
            f"Saved statement audit id={audit.id}, {txn_count} transactions "
            f"({bank_name}/{statement_type.value})"
        )
        return audit


# ── Helpers ──────────────────────────────────────────────────────

def _get_closing(dto, is_cc: bool):
    """Return the best 'closing balance' equivalent from the DTO."""
    if is_cc:
        return getattr(dto, "total_dues", None)
    return getattr(dto, "closing_balance", None)


def _serialize_parse_trace(parse_trace: dict | str | None) -> str | None:
    if parse_trace is None:
        return None
    if isinstance(parse_trace, str):
        return parse_trace
    return json.dumps(parse_trace, sort_keys=True)


def _apply_metadata(audit: StatementAudit, dto, is_cc: bool) -> None:
    """Update statement-level metadata on an existing audit row."""
    if is_cc:
        audit.closing_balance = getattr(dto, "total_dues", None)
        audit.due_date = getattr(dto, "due_date", None)
        audit.credit_limit = getattr(dto, "credit_limit", None)
        audit.available_credit = getattr(dto, "available_credit", None)
        audit.minimum_amount_due = getattr(dto, "minimum_amount_due", None)
        audit.card_holder_name = getattr(dto, "card_holder_name", None)
        audit.card_number = getattr(dto, "card_number", None)
    else:
        audit.opening_balance = getattr(dto, "opening_balance", None)
        audit.closing_balance = getattr(dto, "closing_balance", None)
        audit.account_holder_name = getattr(dto, "account_holder_name", None)
        audit.account_number = getattr(dto, "account_number", None)
        audit.ifsc_code = getattr(dto, "ifsc_code", None)
        audit.branch_name = getattr(dto, "branch_name", None)
