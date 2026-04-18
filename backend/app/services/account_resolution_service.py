"""
Account resolution — find-or-create a BankAccount during statement import.
"""
import logging

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.bank_account import BankAccount

logger = logging.getLogger(__name__)


class AccountResolutionService:
    """Resolve a BankAccount by (bank_name, account_type, account_number)."""

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
        stmt = select(BankAccount).where(
            BankAccount.bank_name == bank_name,
            BankAccount.account_type == account_type,
            BankAccount.account_number == account_number,
        )
        account = db.scalars(stmt).first()

        if account is not None:
            # Update holder_name if we now have one and didn't before
            if holder_name and not account.holder_name:
                account.holder_name = holder_name
                db.flush()
            return account

        # Auto-generate a friendly name
        bank_label = bank_name.replace("_", " ").title()
        type_label = "Savings" if account_type == "SAVINGS" else "Credit Card"
        suffix = f" ••{account_number[-4:]}" if account_number and len(account_number) >= 4 else ""
        friendly_name = f"{bank_label} {type_label}{suffix}"

        account = BankAccount(
            name=friendly_name,
            bank_name=bank_name,
            account_type=account_type,
            account_number=account_number,
            holder_name=holder_name,
        )
        db.add(account)
        db.flush()  # assigns id
        logger.info("Created new bank account: %s (id=%d)", friendly_name, account.id)
        return account
