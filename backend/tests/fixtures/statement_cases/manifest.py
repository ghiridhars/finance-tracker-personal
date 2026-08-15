from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from app.models.enums import BankType, StatementType

ExpectedStatus = Literal["success", "known_failure", "review_required"]

DEFAULT_STATEMENT_CORPUS_ENV_VAR = "FINANCE_TRACKER_STATEMENT_CORPUS_ROOT"
# Secondary corpus for Federal Bank statements (different folder)
FEDERAL_STATEMENT_CORPUS_ENV_VAR = "FINANCE_TRACKER_FEDERAL_CORPUS_ROOT"
DEFAULT_STATEMENT_CORPUS_CANDIDATES = (
    Path(__file__).resolve().parent.parent / "sample_statements",
)


@dataclass(frozen=True, slots=True)
class StatementCase:
    key: str
    bucket: str
    relative_path: str
    bank: BankType
    statement_type: StatementType
    expected_status: ExpectedStatus = "review_required"
    expected_strategy: str | None = None
    minimum_transactions: int | None = None
    expected_opening_balance: str | None = None
    expected_closing_balance: str | None = None
    password_env_var: str | None = None
    corpus_env_var: str | None = None
    notes: str = ""
    tags: tuple[str, ...] = ()

    @property
    def filename(self) -> str:
        return Path(self.relative_path).name

    @property
    def requires_password(self) -> bool:
        return self.password_env_var is not None


# ---------------------------------------------------------------------------
# Federal Bank corpus lives in a different directory — cases referencing it
# use corpus_env_var="FINANCE_TRACKER_FEDERAL_CORPUS_ROOT" so the loader
# can resolve them independently from the primary (BOB/HDFC) corpus.
# ---------------------------------------------------------------------------

PHASE0_CASES: tuple[StatementCase, ...] = (
    # ------------------------------------------------------------------
    # BOB Savings
    # Actual filenames: 0557YYYYMM...pdf  (no BOB-SAVINGS- prefix)
    # ------------------------------------------------------------------
    StatementCase(
        key="bob_savings_2018_legacy_multiline",
        bucket="bob_savings_legacy",
        relative_path="0557201810135605460437.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=38,
        expected_opening_balance="2466.46",
        expected_closing_balance="3278.70",
        password_env_var="FINANCE_TRACKER_BOB_PDF_PASSWORD",
        notes="Known-good 2018 BOB legacy statement.",
        tags=("gold_success", "legacy", "bob", "savings"),
    ),
    StatementCase(
        key="bob_savings_2021_transition_multiline",
        bucket="bob_savings_transition",
        relative_path="0557202108019804601356.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=8,
        expected_opening_balance="1952.44",
        expected_closing_balance="2917.44",
        password_env_var="FINANCE_TRACKER_BOB_PDF_PASSWORD",
        notes="Known-good 2021 BOB transition statement with fragmented tables.",
        tags=("gold_success", "transition", "bob", "savings"),
    ),
    StatementCase(
        key="bob_savings_2019_legacy_review",
        bucket="bob_savings_legacy",
        relative_path="0557201908061101591356.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=20,
        expected_opening_balance="2525.28",
        expected_closing_balance="4757.58",
        password_env_var="FINANCE_TRACKER_BOB_PDF_PASSWORD",
        notes="Legacy BOB baseline sample promoted to a gold success case.",
        tags=("gold_success", "legacy", "bob", "savings"),
    ),
    StatementCase(
        key="bob_savings_2020_transition_review",
        bucket="bob_savings_transition",
        relative_path="0557202012087800561356.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=21,
        expected_opening_balance="2164.68",
        expected_closing_balance="1865.72",
        password_env_var="FINANCE_TRACKER_BOB_PDF_PASSWORD",
        notes="BOB transition-period sample promoted to a gold success case.",
        tags=("gold_success", "bob", "savings", "transition"),
    ),
    StatementCase(
        key="bob_savings_2025_current_review",
        bucket="bob_savings_current",
        relative_path="0557202505069903221356.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=20,
        expected_opening_balance="2120.95",
        expected_closing_balance="5000.00",
        password_env_var="FINANCE_TRACKER_BOB_PDF_PASSWORD",
        notes="Recent BOB sample promoted to a gold success case.",
        tags=("gold_success", "bob", "savings", "current"),
    ),
    StatementCase(
        key="bob_estmt_september_2018_review",
        bucket="legacy_estmt",
        relative_path="Estmt_September_2018_XXXXX1356_0557_361.pdf",
        bank=BankType.BOB,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=79,
        expected_opening_balance="1982.68",
        expected_closing_balance="2466.46",
        password_env_var="FINANCE_TRACKER_BOB_PDF_PASSWORD",
        notes="Legacy Estmt-format sample promoted to a gold success case.",
        tags=("gold_success", "legacy", "bob", "savings"),
    ),
    # ------------------------------------------------------------------
    # HDFC Savings
    # Actual filenames: Ghiridhar__S_DDMMYYYY_NNNNNNNNN.pdf
    # ------------------------------------------------------------------
    StatementCase(
        key="hdfc_savings_2025_oct_regression",
        bucket="hdfc_savings",
        relative_path="Ghiridhar__S_31102025_150053750.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=11,
        expected_opening_balance="80320.00",
        expected_closing_balance="0.00",
        password_env_var="FINANCE_TRACKER_HDFC_SAVINGS_PDF_PASSWORD",
        notes="Oct 2025 HDFC savings statement — original regression that exposed UPI ref parsing bug.",
        tags=("gold_success", "regression", "hdfc", "savings"),
    ),
    StatementCase(
        key="hdfc_savings_2025_feb_review",
        bucket="hdfc_savings",
        relative_path="Ghiridhar__S_28022025_235652158.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=2,
        expected_opening_balance="20000.00",
        expected_closing_balance="67723.00",
        password_env_var="FINANCE_TRACKER_HDFC_SAVINGS_PDF_PASSWORD",
        notes="HDFC savings monthly statement promoted to a gold success case.",
        tags=("gold_success", "hdfc", "savings"),
    ),
    StatementCase(
        key="hdfc_savings_2025_dec_review",
        bucket="hdfc_savings",
        relative_path="Ghiridhar__S_31122025_195333115.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=4,
        expected_opening_balance="0.00",
        expected_closing_balance="80488.00",
        password_env_var="FINANCE_TRACKER_HDFC_SAVINGS_PDF_PASSWORD",
        notes="HDFC savings year-end sample promoted to a gold success case.",
        tags=("gold_success", "hdfc", "savings"),
    ),
    StatementCase(
        key="hdfc_savings_2026_apr_review",
        bucket="hdfc_savings",
        relative_path="Ghiridhar__S_30042026_213013410.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="multiline",
        minimum_transactions=4,
        expected_opening_balance="19417.00",
        expected_closing_balance="110375.00",
        password_env_var="FINANCE_TRACKER_HDFC_SAVINGS_PDF_PASSWORD",
        notes="Latest HDFC savings sample promoted to a gold success case.",
        tags=("gold_success", "hdfc", "savings", "current"),
    ),
    # ------------------------------------------------------------------
    # HDFC Credit Card — card ending 4632
    # Actual filenames: 4632XXXXXXXXXX18_17-MM-YYYY[_NNN].PDF
    # ------------------------------------------------------------------
    StatementCase(
        key="hdfc_cc_4632_2022_review",
        bucket="hdfc_cc_4632",
        relative_path="4632XXXXXXXXXX18_17-02-2022.PDF",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_env_var="FINANCE_TRACKER_HDFC_CC_PDF_PASSWORD",
        notes="HDFC credit-card baseline sample for the 4632 variant.",
        tags=("review", "hdfc", "credit_card"),
    ),
    StatementCase(
        key="hdfc_cc_4632_2024_review",
        bucket="hdfc_cc_4632",
        relative_path="4632XXXXXXXXXX18_17-09-2024.PDF",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_env_var="FINANCE_TRACKER_HDFC_CC_PDF_PASSWORD",
        notes="HDFC credit-card 4632 variant mid-range sample.",
        tags=("review", "hdfc", "credit_card"),
    ),
    StatementCase(
        key="hdfc_cc_4632_2026_review",
        bucket="hdfc_cc_4632",
        relative_path="4632XXXXXXXXXX18_17-05-2026_550.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_env_var="FINANCE_TRACKER_HDFC_CC_PDF_PASSWORD",
        notes="Latest HDFC credit-card 4632 sample in the current corpus.",
        tags=("review", "hdfc", "credit_card", "current"),
    ),
    # ------------------------------------------------------------------
    # HDFC Credit Card — UPI-linked card ending 6530
    # Actual filenames: 6530XXXXXXXXXX79_17-MM-YYYY[_NNN].PDF
    # ------------------------------------------------------------------
    StatementCase(
        key="hdfc_cc_upi_2024_review",
        bucket="hdfc_cc_upi_6530",
        relative_path="6530XXXXXXXXXX79_17-07-2024.PDF",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_env_var="FINANCE_TRACKER_HDFC_CC_PDF_PASSWORD",
        notes="HDFC UPI-linked card variant baseline sample.",
        tags=("review", "hdfc", "credit_card", "upi_variant"),
    ),
    StatementCase(
        key="hdfc_cc_upi_2025_review",
        bucket="hdfc_cc_upi_6530",
        relative_path="6530XXXXXXXXXX79_17-02-2025.PDF",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_env_var="FINANCE_TRACKER_HDFC_CC_PDF_PASSWORD",
        notes="HDFC UPI-linked card variant mid-range sample.",
        tags=("review", "hdfc", "credit_card", "upi_variant"),
    ),
    StatementCase(
        key="hdfc_cc_upi_2026_review",
        bucket="hdfc_cc_upi_6530",
        relative_path="6530XXXXXXXXXX79_17-05-2026_632.pdf",
        bank=BankType.HDFC,
        statement_type=StatementType.CREDIT_CARD,
        password_env_var="FINANCE_TRACKER_HDFC_CC_PDF_PASSWORD",
        notes="Latest HDFC UPI-linked card variant sample in the current corpus.",
        tags=("review", "hdfc", "credit_card", "upi_variant", "current"),
    ),
    # ------------------------------------------------------------------
    # Federal Bank Savings
    # Located in a separate directory — uses FINANCE_TRACKER_FEDERAL_CORPUS_ROOT.
    # Actual filenames: ACC_STATEMENT_XXXXX1489_DDMMMYYYY_DDMMMYYYY_NNN.pdf
    # ------------------------------------------------------------------
    StatementCase(
        key="federal_savings_2026_may_table",
        bucket="federal_savings",
        relative_path="ACC_STATEMENT_XXXXX1489_03MAY2026_02JUN2026_1780451781673419.pdf",
        bank=BankType.FEDERAL_BANK,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="table",
        minimum_transactions=15,
        password_env_var="FINANCE_TRACKER_FEDERAL_PDF_PASSWORD",
        corpus_env_var="FINANCE_TRACKER_FEDERAL_CORPUS_ROOT",
        notes="Federal Bank May 2026 statement. Uses table strategy (integer amounts).",
        tags=("gold_success", "federal", "savings", "current"),
    ),
    StatementCase(
        key="federal_savings_2026_apr_table",
        bucket="federal_savings",
        relative_path="ACC_STATEMENT_XXXXX1489_03APR2026_02MAY2026_1777766111676932.pdf",
        bank=BankType.FEDERAL_BANK,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="table",
        minimum_transactions=5,
        password_env_var="FINANCE_TRACKER_FEDERAL_PDF_PASSWORD",
        corpus_env_var="FINANCE_TRACKER_FEDERAL_CORPUS_ROOT",
        notes="Federal Bank Apr 2026 statement.",
        tags=("gold_success", "federal", "savings"),
    ),
    StatementCase(
        key="federal_savings_2026_jun_table",
        bucket="federal_savings",
        relative_path="ACC_STATEMENT_XXXXX1489_03JUN2026_02JUL2026_1783043075270610.pdf",
        bank=BankType.FEDERAL_BANK,
        statement_type=StatementType.SAVINGS,
        expected_status="success",
        expected_strategy="table",
        minimum_transactions=5,
        password_env_var="FINANCE_TRACKER_FEDERAL_PDF_PASSWORD",
        corpus_env_var="FINANCE_TRACKER_FEDERAL_CORPUS_ROOT",
        notes="Federal Bank Jun 2026 statement — most recent available.",
        tags=("gold_success", "federal", "savings", "current"),
    ),
)


def assertable_phase0_cases() -> tuple[StatementCase, ...]:
    return tuple(case for case in PHASE0_CASES if case.expected_status != "review_required")


def review_phase0_cases() -> tuple[StatementCase, ...]:
    return tuple(case for case in PHASE0_CASES if case.expected_status == "review_required")