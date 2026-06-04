# PDF Statement Parsing — Strategy Reference

The parser engine has been refactored from a monolithic `generic_pdf_parser.py` file into a modular, multi-strategy parsing framework located at [backend/app/parsing](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing).

It extracts transactions from bank statement PDFs without bank-specific code by running a series of heuristic parsing strategies. It uses a routing layer to dynamically order and filter strategies based on statement templates, collects candidate parsing results, selects the best fit, and falls back to LLM-based parsing only if all local strategies fail.

---

## Modular Architecture Overview

The parsing module is structured as follows:

*   **Entry Point & Orchestration:**
    *   [generic_pdf.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/generic_pdf.py) — Compatibility entry class `GenericPdfParser` and execution runner `parse_generic_pdf_statement()`.
    *   [engine.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/engine.py) — Parsing engine abstractions.
*   **Routing & Classification:**
    *   [routing.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/routing.py) — Matches a document to a routing configuration (`StrategyRoute`).
    *   [classifiers/template_classifier.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/classifiers/template_classifier.py) — Heuristic scoring based on expected word fragments in raw text.
    *   [profiles/](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/profiles/) — Strategy profile registry and bank manifests (e.g., [hdfc_credit_card_v1.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/profiles/manifests/hdfc_credit_card_v1.py)).
*   **Extraction Layer:**
    *   [extraction/pdf_text.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/extraction/pdf_text.py) — Extracts raw text from PDFs using `pymupdf (fitz)`.
    *   [extraction/pdf_tables.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/extraction/pdf_tables.py) — Extracts structured table grids using `pdfplumber`.
    *   [extraction/statement_metadata.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/extraction/statement_metadata.py) — Parses fields like account/card numbers and statement periods.
*   **Heuristic Strategies:**
    *   [strategies/table_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/table_strategy.py) — Strategy 1: Grid table layout parsing.
    *   [strategies/single_line_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/single_line_strategy.py) — Strategy 2: Single-line regex matching.
    *   [strategies/multiline_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/multiline_strategy.py) — Strategies 3-4: Multi-line CC and generic savings parses.
*   **Result Verification & Fallbacks:**
    *   [validation.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/validation.py) — Enforces balance and transaction sanity rules.
    *   [result_selection.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/result_selection.py) — Picks the candidate result with the highest transaction count.
    *   [fallbacks/](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/fallbacks/) — Handles LLM routing (Gemini/Ollama) and manual review fallback generation.

---

## Pipeline Flow

```
Upload / Local-Sync / Google-Drive-Sync
        │
        ▼
ParserService.parse_statement()
        │
        ├─ validate PDF (size, magic bytes)
        │
        ├─ GenericPdfParser.parse()
        │       │
        │       └─ parse_generic_pdf_statement()
        │               │
        │               ├─ Extract tables (pdfplumber)
        │               ├─ Extract text document (PyMuPDF)
        │               │
        │               ├─ resolve_strategy_route()
        │               │       └─ classify_template() using Profiles Registry
        │               │
        │               ├─ For each strategy in route.strategy_order:
        │               │       └─ Run strategy function -> candidate ParseResult
        │               │
        │               ├─ select_best_result() (highest transaction count)
        │               │
        │               └─ If all fail ──► LLM Fallback (Gemini / Ollama)
        │
        └─ apply_account_identity() + validate_statement()
```

---

## Strategy Details

### Strategy 1 — Table Extraction
*   **Module:** [strategies/table_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/table_strategy.py) (`try_table_strategy`)
*   **Method:** Utilizes cell bounding boxes from `pdfplumber` to extract structured grids. Looks for header rows matching `patterns.py` column lists, maps indices, and walks cells sequentially.
*   **Target:** Clean tabular PDFs (e.g., Federal Bank, certain HDFC savings statements).

### Strategy 2 — Single-Line Text Parsing
*   **Module:** [strategies/single_line_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/single_line_strategy.py) (`try_single_line_strategy`)
*   **Method:** Processes the document line-by-line. Uses `LEADING_DATE_RE` to find transaction starts, scans numeric tokens from the right side of the line for Debit/Credit/Balance, and groups remaining text as the description.
*   **Target:** Statements where every transaction fits on a single line.

### Strategy 3a — Credit Card Multi-Line (Date/Time Format)
*   **Module:** [strategies/multiline_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/multiline_strategy.py) (`try_cc_multiline_strategy`)
*   **Method:** Looks for transaction headers containing date|time markers (e.g., `18/02/2026 | 08:48`). Collects description lines until it matches a currency-prefixed amount line (e.g., `C 3,835.00` or `+ C 9,579.00`).
*   **Target:** Modern HDFC Credit Card statements.

### Strategy 3b — Credit Card Simple Multi-Line (Date / Desc / Amount)
*   **Module:** [strategies/multiline_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/multiline_strategy.py) (`try_cc_simple_multiline_strategy`)
*   **Method:** Matches standalone date lines, then buffers subsequent description lines until a currency-stripped numeric amount line (e.g., `1,329.00` or `330.00 Cr`) is found.
*   **Target:** Older HDFC Credit Card statements and HDFC UPI Credit Cards.

### Strategy 4 — Generic Multi-Line Text Parsing
*   **Module:** [strategies/multiline_strategy.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/strategies/multiline_strategy.py) (`try_multiline_strategy`)
*   **Method:** Parses vertical transaction blocks where fields (serial, date, value date, description, debit, credit, balance) appear on separate lines.
*   **Target:** Savings statements with vertical cell wrapping (e.g., Bank of Baroda).

---

## Result Selection & Verification

The strategy runner collects all candidate `ParseResult`s that complete successfully. 

`select_best_result()` evaluates these candidates and chooses the one with the highest transaction count. This allows the system to choose the table parser if it works, but dynamically fall back to a text-line parse if the table parser only captured a subset of transactions due to paging structures.

Once selected, the statement undergoes `validate_statement()` which checks:
1. Date sequencing consistency.
2. Sign-correctness of transaction amounts.
3. Balance mathematical validation (if opening/closing balance metadata is present).

---

## How to Add or Modify Parsing Logic

### 1. Adding a New Strategy Profile
If a specific bank has a unique text formatting order, you can guide the router by adding a Strategy Profile:
1. Create a new file in `app/parsing/profiles/manifests/` (e.g., `axis_savings_v1.py`).
2. Define a `StrategyProfile` specifying the target `BankType`, `StatementType`, `required_text` identifying tokens, and the `preferred_order` of strategies.
3. Register it inside `app/parsing/profiles/manifests/__init__.py`.

### 2. Modifying Strategy Mechanics
*   To edit column mappings or regex rules, update [app/parsing/patterns.py](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/patterns.py).
*   To change extraction behavior, modify the modules in the [extraction/](file:///home/ghiridhars/Codebase/finance-tracker-personal/backend/app/parsing/extraction/) subdirectory.
