"""
Account resolution — find-or-create a BankAccount during statement import.
"""
import logging
import re

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.bank_account import BankAccount

logger = logging.getLogger(__name__)


class AccountResolutionService:
    """Resolve a BankAccount by normalized bank/type/account identity."""

    @staticmethod
    def _normalize_account_number(
        account_number: str | None,
        account_type: str | None = None,
    ) -> str | None:
        """Collapse formatting so spaced and compact masked identifiers match."""
        if not account_number:
            return None

        normalized = re.sub(r"[\s-]+", "", account_number.strip().upper())
        normalized = normalized.replace("*", "X")

        # Savings accounts should not use word-only placeholders like OPEN or JOINT.
        if account_type == "SAVINGS" and not any(ch.isdigit() for ch in normalized):
            return None

        return normalized

    @staticmethod
    def _normalized_account_number_expr():
        return func.replace(
            func.replace(
                func.replace(func.upper(BankAccount.account_number), " ", ""),
                "-",
                "",
            ),
            "*",
            "X",
        )

    @staticmethod
    def resolve_or_create(
        db: Session,
        bank_name: str,
        account_type: str,
        account_number: str | None,
        holder_name: str | None = None,
    ) -> BankAccount:
        """
        Look up an existing account or create one on first import.

        Parameters
        ----------
        bank_name : str
            BankType value, e.g. "HDFC", "BOB".
        account_type : str
            "SAVINGS" or "CREDIT_CARD".
        account_number : str | None
            Account or card number (may be masked).
        holder_name : str | None
            Name extracted from the statement.

        Returns
        -------
        BankAccount
            Existing or newly created account (flushed, has an id).
        """
        normalized_account_number = AccountResolutionService._normalize_account_number(
            account_number,
            account_type=account_type,
        )

        stmt = select(BankAccount).where(
            BankAccount.bank_name == bank_name,
            BankAccount.account_type == account_type,
        )

        if normalized_account_number is None:
            stmt = stmt.where(BankAccount.account_number.is_(None))
        else:
            stmt = stmt.where(
                AccountResolutionService._normalized_account_number_expr()
                == normalized_account_number
            )

        account = db.scalars(stmt.order_by(BankAccount.id)).first()

        if account is not None:
            # Update holder_name if we now have one and didn't before
            if holder_name and not account.holder_name:
                account.holder_name = holder_name
                db.flush()
            return account

        # Auto-generate a friendly name
        bank_label = bank_name.replace("_", " ").title()
        type_label = "Savings" if account_type == "SAVINGS" else "Credit Card"
        stored_account_number = normalized_account_number
        if stored_account_number is None and account_type != "SAVINGS":
            stored_account_number = account_number
        suffix = (
            f" ••{stored_account_number[-4:]}"
            if stored_account_number and len(stored_account_number) >= 4
            else ""
        )
        friendly_name = f"{bank_label} {type_label}{suffix}"

        account = BankAccount(
            name=friendly_name,
            bank_name=bank_name,
            account_type=account_type,
            account_number=stored_account_number,
            holder_name=holder_name,
        )
        db.add(account)
        db.flush()  # assigns id
        logger.info("Created new bank account: %s (id=%d)", friendly_name, account.id)
        return account
