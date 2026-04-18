# PDF Statement Parsing — Strategy Reference

The generic PDF parser (`backend/app/parsers/generic_pdf_parser.py`) extracts
transactions from bank statement PDFs without any bank-specific configuration.
It tries multiple strategies in order and returns the result of the first one
that succeeds. If all strategies fail, the pipeline falls back to an LLM-based
parser (when available).

---

## Pipeline overview

```
Upload / Local-sync / Google-Drive-sync
        │
        ▼
ParserService.parse_statement()
        │
        ├─ validate PDF (size, magic bytes)
        │
        ├─ GenericPdfParser.parse(file, statement_type)
        │       │
        │       ├─ Strategy 1  — Table extraction
        │       ├─ Strategy 2  — Single-line text
        │       ├─ Strategy 3a — Credit-card multi-line (date|time format)
        │       ├─ Strategy 3b — Credit-card simple multi-line (date/desc/amount)
        │       ├─ Strategy 4  — Generic multi-line text
        │       │
        │       └─ failure ──► LLM fallback (Gemini / Ollama)
        │
        └─ _apply_account_identity() → result dict
```

**Strategy ordering matters.** CC-specific strategies (3a, 3b) run before the
generic multi-line strategy (4) to prevent false positives where Strategy 4
picks up header dates from credit-card PDFs.

---

## Text extraction

Two libraries are used for different purposes:

| Library       | Used by      | Strength                          |
|---------------|--------------|-----------------------------------|
| **pdfplumber** | Strategy 1   | Accurate table/cell extraction    |
| **pymupdf (fitz)** | Strategies 2–4 | Fast raw text extraction   |

`extract_raw_text()` concatenates text from every page using pymupdf, falling
back to pdfplumber if pymupdf returns nothing. A debug mode writes the
extracted text to `last_parsed_text.txt` beside the PDF.

---

## Strategy 1 — Table extraction

**Method:** `_try_table_strategy(pdf, statement_type)`

**Target format:** PDFs where pdfplumber can detect proper table structures
with headers and rows (e.g., Federal Bank, some HDFC savings statements).

**How it works:**

1. Call `pdfplumber.extract_tables()` on every page.
2. Find the header row by matching column names against known patterns
   (`DATE_PATTERNS`, `DESCRIPTION_PATTERNS`, `DEBIT_PATTERNS`, etc. from
   `patterns.py`).
3. Map column indices using `map_columns()`.
4. Parse each data row: extract date, description, debit, credit, balance via
   the mapped column positions.
5. Build the result schema.

**Quick check:** Needs at least a date column plus one of debit / credit /
amount.

**Debit vs Credit:** If separate debit and credit columns exist, values are
read directly. With a single amount column, negative values are treated as
debits and positive as credits.

**Example input (table cells):**

```
┌────────────┬──────────────────────────┬──────────┬──────────┬────────────┐
│ Date       │ Description              │ Debit    │ Credit   │ Balance    │
├────────────┼──────────────────────────┼──────────┼──────────┼────────────┤
│ 01/01/2024 │ ATM WITHDRAWAL           │ 5,000.00 │          │ 45,000.00  │
│ 03/01/2024 │ SALARY CREDIT            │          │ 50,000.00│ 95,000.00  │
└────────────┴──────────────────────────┴──────────┴──────────┴────────────┘
```

---

## Strategy 2 — Single-line text parsing

**Method:** `_try_text_strategy(raw_text, statement_type)`

**Target format:** PDFs where every transaction fits on a single line with the
date at the start and one or more numeric amount tokens at the end.

**How it works:**

1. Scan each line for a leading date using `LEADING_DATE_RE`:
   ```
   ^(?:\d{1,4}\s+)?(\d{2}[/-]\d{2}[/-]\d{2,4})
   ```
   An optional serial number prefix (`1`, `23`, etc.) is tolerated.
2. Walk tokens from the right side of the line, collecting amount-like tokens
   (matching `DECIMAL_AMOUNT_RE` or `INTEGER_AMOUNT_RE`).
3. Everything between the date and the amounts is the description.
4. Lines without a leading date are appended to the previous transaction's
   description (continuation lines).
5. Classify amounts with `_classify_amounts()`:
   - 3 tokens → debit, credit, balance
   - 2 tokens → amount, balance
   - 1 token  → amount only
6. Build the result schema.

**Quick check:** Need ≥2 amount tokens for savings, ≥1 for credit cards.
If no decimal amounts are found at all, need ≥3 lines.

**Example input (raw text):**

```
01/01/2024  ATM WITHDRAWAL NEAR HOME      5,000.00          45,000.00
03/01/2024  SALARY CREDIT                           50,000.00 95,000.00
04/01/2024  UPI/DR/123456789/SWIGGY        600.00            94,400.00
```

---

## Strategy 3a — Credit-card multi-line (date|time format)

**Method:** `_try_cc_multiline_strategy(raw_text)`

**Only runs for:** `StatementType.CREDIT_CARD`

**Target format:** HDFC Bank credit card statements (newer format, 2024+) where
each transaction starts with a date|time line and amounts use a currency prefix
(`C`, `₹`, `$`).

**Key regexes:**

| Pattern | Regex | Matches |
|---------|-------|---------|
| `_CC_DATE_TIME_RE` | `^(\d{2}[/-]\d{2}[/-]\d{2,4})\s*(?:\|\|\s)\s*\d{2}:\d{2}` | `18/02/2026\| 08:48` or `30/03/2024 15:01` |
| `_CC_AMOUNT_RE` | `^(\+)?\s*[C₹$]\s*([\d,]+\.\d{2})$` | `C 3,835.00`, `+ C 9,579.00` |

**How it works:**

1. **Quick check:** Count lines matching `_CC_DATE_TIME_RE`. Need ≥2.
2. For each date|time line:
   - Parse the date.
   - Collect subsequent lines as description until an amount line is found.
   - Amount line must match `_CC_AMOUNT_RE` (currency prefix required).
   - Skip single-character lines (category markers like `l`).
   - Stop collecting if the next date|time line is encountered.
3. Credit vs Debit: `+` prefix on the amount line → CREDIT (payment/refund),
   otherwise DEBIT (purchase).
4. Extract `(Ref# ...)` from description if present.
5. Strip leading `EMI ` prefix from descriptions.
6. Build result via `_build_credit_card_result()`.

**Example input (raw text):**

```
18/02/2026| 08:48
BPPY CC PAYMENT DP016049084815AdpUZ (Ref# ST260500083000010182109)
+  C 9,579.00
l
06/03/2026| 16:38
EMI
ACKOMumbai
 C 3,835.00
l
```

---

## Strategy 3b — Credit-card simple multi-line (date / desc / amount)

**Method:** `_try_cc_simple_multiline_strategy(raw_text)`

**Only runs for:** `StatementType.CREDIT_CARD`

**Target format:** Older HDFC Bank credit card statements and HDFC UPI credit
card statements where transactions are in a simple three-part vertical layout:
date line, description line(s), amount line.

**Key regexes:**

| Pattern | Regex | Matches |
|---------|-------|---------|
| `_CC_SIMPLE_DATE_RE` | `^(\d{2}[/-]\d{2}[/-]\d{2,4})(?:\s+\d{2}:\d{2}(?::\d{2})?)?$` | `02/02/2022`, `30/03/2024 15:01:42` |
| `_CC_SIMPLE_AMOUNT_RE` | `^([\d,]+\.\d{2})\s*(?:(Cr\|CR\|cr))?\s*$` | `948.00`, `330.00 Cr`, `3,168.00 Cr` |

**How it works:**

1. **Quick check:** Count standalone date lines (with optional time). Need ≥3.
2. For each date line:
   - Parse the date.
   - Collect description lines until an amount line is hit.
   - Skip blank lines within a transaction block.
   - Stop and discard if a non-transaction keyword is hit:
     `reward points`, `opening balance`, `closing balance`,
     `cash points`, `important information`, `total dues`,
     `payment due`, `credit limit`.
   - Stop if the next date line is reached (amount not found → skip).
3. Credit vs Debit: `Cr` / `CR` / `cr` suffix → CREDIT, otherwise DEBIT.
4. Extract `(Ref# ...)` from description if present.
5. Skip transactions with zero/negative amounts or empty descriptions.
6. Build result via `_build_credit_card_result()`.

**Example input — HDFC CC (no time):**

```
GHIRIDHAR S

02/02/2022
AMAZON SELLER SERVICES MUMBAI
1,329.00

05/02/2022
WWW BLUETOKAICOFFEE COMGURGAON
99.00

08/02/2022
AMAZON SELLER SERVICES MUMBAI
330.00 Cr

16/02/2022
NETBANKING TRANSFER (Ref# 00000000000216008733794)
3,168.00 Cr
Reward Points Summary
```

**Example input — HDFC UPI CC (with time):**

```
30/03/2024 15:01:42
UPI-Swiggy
529.00

03/04/2024 14:51:38
UPI-SWIGGY
536.00

05/04/2024 11:56:59
UPI-SWIGGY
600.00
```

---

## Strategy 4 — Generic multi-line text parsing

**Method:** `_try_multiline_strategy(raw_text, statement_type)`

**Target format:** Savings account statements (primarily Bank of Baroda) where
every field is on its own line, typically with serial numbers. Each transaction
is a vertical block of lines.

**Key regexes:**

| Pattern | Regex | Matches |
|---------|-------|---------|
| `_ML_DATE_RE` | `^\d{2}[/-]\d{2}[/-]\d{2,4}$` | `01/01/2024` (exact, no extra text) |
| `_ML_SERIAL_RE` | `^\d{1,4}$` | `1`, `23`, `456` |
| `_ML_AMOUNT_RE` | `^[\d,]+(?:\.\d{1,2})?$` | `5,000.00`, `50000` |
| `_ML_DASH_RE` | `^-$` | `-` (indicates zero in a column) |

**How it works:**

1. **Quick check:** Count standalone date lines. Need ≥4.
2. For each block, parse fields in this fixed order:
   - Optional serial number (`_ML_SERIAL_RE`)
   - Transaction date (required, `_ML_DATE_RE`)
   - Optional value date (second date line)
   - Description lines (collected until an amount or dash is found)
   - Debit amount or `-` (required)
   - Credit amount or `-`
   - Balance (required amount)
3. A transaction must have a valid date and at least one of debit/credit.
4. Build result via `_build_savings_result()` or `_build_credit_card_result()`.

**Example input (raw text):**

```
1
01/01/2024
01/01/2024
ATM WDL-CASH
5,000.00
-
45,000.00

2
03/01/2024
03/01/2024
NEFT/SALARY/EMPLOYER
-
50,000.00
95,000.00
```

---

## Shared utilities

### `patterns.py`

Provides column-header matching patterns and value parsers used across
strategies:

| Function / Constant  | Purpose |
|----------------------|---------|
| `parse_date(value)`  | Parse a date string using `dateutil.parser` with `dayfirst=True`. Returns `datetime.date` or `None`. |
| `parse_amount(value)` | Strip currency symbols (`₹`, `$`, `Rs.`), commas, and whitespace; return `Decimal` or `None`. |
| `map_columns(header)` | Match header cell text against known column patterns and return a dict of `{role: index}`. |
| `is_table_header(row)` | Check if a row contains enough header-like cells to be considered a header. |
| `NOISE_PATTERN`       | Regex for page footers, bank URLs, disclaimers, etc. that should be skipped. |
| `LEADING_DATE_RE`     | Regex for lines starting with an optional serial + date. |
| `DECIMAL_AMOUNT_RE`   | Regex for decimal amounts like `5,000.00`. |

### Result building

| Method | Schema | Notes |
|--------|--------|-------|
| `_build_savings_result(txns)` | `SavingsAccountStatementSchema` | Calculates opening/closing balance, date range |
| `_build_credit_card_result(txns)` | `CreditCardStatementSchema` | Uses single `amount` field (debit or credit), sets `statement_date` to max transaction date |

### Metadata extraction

`extract_metadata(text)` scans the full text for:
- Statement period (`period_from`, `period_to`)
- Account number
- Credit card number

This metadata is attached to the result schema but is not required for
transaction parsing to succeed.

---

## Which banks hit which strategy

| Bank / Card | Statement type | Strategy | Key characteristic |
|-------------|---------------|----------|--------------------|
| Federal Bank | Savings | 1 (Table) | Clean table structure |
| HDFC Savings | Savings | 1 (Table) or 2 (Single-line) | Varies by statement age |
| HDFC CC (2024+ format) | Credit Card | 3a (CC multi-line) | `DD/MM/YYYY\| HH:MM` + `C amount` |
| HDFC CC (older format) | Credit Card | 3b (CC simple) | `DD/MM/YYYY` / desc / `amount [Cr]` |
| HDFC UPI CC | Credit Card | 3b (CC simple) | `DD/MM/YYYY HH:MM:SS` / desc / amount |
| Bank of Baroda | Savings | 4 (Generic multi-line) | Serial / date / desc / debit / credit / balance on separate lines |

---

## Adding a new strategy

1. Add a private method `_try_<name>_strategy(...)` in `GenericPdfParser`.
2. Add a dispatch call in `parse()` at the appropriate position.
   - More specific strategies should run before more generic ones.
   - CC-specific strategies should be guarded by
     `if statement_type == StatementType.CREDIT_CARD`.
3. Return `None` to signal "this strategy doesn't apply" (next strategy tries).
4. Return `ParseResult.failure(...)` only for hard errors.
5. Return `self._build_savings_result(txns)` or
   `self._build_credit_card_result(txns)` on success.
6. Include a **quick check** (e.g., count date lines) at the top of the method
   so it exits fast when the format doesn't match.
