"""
Unit tests for UpiService update deduplication.
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base
from app.models.upi import UpiId
from app.services.upi_service import UpiService


def _make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    return session_factory()


def test_update_upi_handle_collision_auto_deletes_edited_entry():
    db = _make_session()
    # Create original entry
    orig = UpiService.create(
        db,
        upi_handle="user@bank",
        label="Original",
    )

    # Create second entry
    edited = UpiService.create(
        db,
        upi_handle="user2@bank",
        label="To Edit",
    )

    # Edit second entry's handle to match original entry's handle
    result = UpiService.update(
        db,
        edited.id,
        upi_handle="user@bank",
    )

    # Returned object is the original entry
    assert result is not None
    assert result.id == orig.id
    assert result.upi_handle == "user@bank"
    assert result.label == "Original"

    # Edited entry is auto-deleted from DB
    deleted = db.query(UpiId).filter(UpiId.id == edited.id).first()
    assert deleted is None

    # Total UPI entries in DB is 1
    total = db.query(UpiId).count()
    assert total == 1


def test_extract_upi_id_handles_spaces_and_hyphens():
    from app.services.categorization_service import extract_upi_id
    assert extract_upi_id("UPI/virenderganes h84-1@okicici/500") == "virenderganesh84-1@okicici"
    assert extract_upi_id("UPI/s-ghiridhars@ybl/PAYMENT") == "s-ghiridhars@ybl"
    assert extract_upi_id("9496391900@yesc red") == "9496391900@yescred"


def test_match_upi_id_supports_provider_alias_and_prefix():
    from app.services.categorization_service import match_upi_id
    db = _make_session()
    UpiService.create(db, upi_handle="user@okhdfcbank", label="HDFC Account", category_id=42)
    
    # Matching truncated handle user@okhdf via alias or prefix match
    cat_id, is_own, matched = match_upi_id(db, "UPI/user@okhdf/500")
    assert cat_id == 42
    assert matched in ("user@okhdfcbank", "user@okhdf")


def test_resolve_bank_account_from_upi_suffix_match():
    """_resolve_bank_account_from_upi resolves BankAccount.id via 6-digit suffix match."""
    from app.models.bank_account import BankAccount
    from app.services.categorization_service import _resolve_bank_account_from_upi

    db = _make_session()

    # Register an own UPI with account_identifier
    UpiService.create(
        db,
        upi_handle="ghiridhars@ybl",
        label="My HDFC",
        is_own=True,
        account_identifier="05570100013649",
    )

    # Create corresponding BankAccount (account_number ends with same 6 digits)
    acct = BankAccount(
        name="HDFC Savings",
        bank_name="HDFC",
        account_type="SAVINGS",
        account_number="05570100013649",
    )
    db.add(acct)
    db.commit()

    resolved_id = _resolve_bank_account_from_upi(db, "ghiridhars@ybl")
    assert resolved_id == acct.id


def test_resolve_bank_account_from_upi_no_account_identifier():
    """Returns None when UpiId has no account_identifier."""
    from app.services.categorization_service import _resolve_bank_account_from_upi

    db = _make_session()
    UpiService.create(db, upi_handle="ghost@paytm", is_own=True)

    result = _resolve_bank_account_from_upi(db, "ghost@paytm")
    assert result is None


def test_auto_categorize_sets_target_bank_account_id_on_own_upi():
    """auto_categorize populates target_bank_account_id when own UPI matches a BankAccount."""
    from app.models.bank_account import BankAccount
    from app.services.categorization_service import auto_categorize

    db = _make_session()

    UpiService.create(
        db,
        upi_handle="ghiridhars@ybl",
        label="My HDFC",
        is_own=True,
        account_identifier="05570100013649",
    )
    acct = BankAccount(
        name="HDFC Savings",
        bank_name="HDFC",
        account_type="SAVINGS",
        account_number="05570100013649",
    )
    db.add(acct)
    db.commit()

    result, is_own = auto_categorize(
        db,
        description="UPI/ghiridhars@ybl/Transfer",
    )
    assert is_own is True
    assert result.target_bank_account_id == acct.id

