"""add transfer linking fields to unified_transactions

Revision ID: a1b2c3d4e5f6
Revises: 084fc04be00e
Create Date: 2026-03-21 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = '084fc04be00e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "unified_transactions",
        sa.Column("is_transfer", sa.Boolean(), nullable=False, server_default="0"),
    )
    op.add_column(
        "unified_transactions",
        sa.Column("transfer_group_id", sa.String(36), nullable=True),
    )
    op.add_column(
        "unified_transactions",
        sa.Column(
            "transfer_type",
            sa.Enum("INTERNAL_TRANSFER", "CC_BILL_PAYMENT", name="transfertype"),
            nullable=True,
        ),
    )
    op.create_index("ix_unified_transfer_group_id", "unified_transactions", ["transfer_group_id"])


def downgrade() -> None:
    op.drop_index("ix_unified_transfer_group_id", table_name="unified_transactions")
    op.drop_column("unified_transactions", "transfer_type")
    op.drop_column("unified_transactions", "transfer_group_id")
    op.drop_column("unified_transactions", "is_transfer")
