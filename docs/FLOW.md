# Finance Tracker — User Flows & API Reference

All identified user flows with their corresponding API endpoints.

---

## 1. Statement Parsing & Import Flow

**Overview:** Upload a bank statement (PDF or CSV) or sync a local directory, parse it into generic DTOs, resolve the target Bank Account, and save the transaction list into the unified database.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Import[import_screen.dart\nSegmentedButton]
        
        Prov_Single[statements_provider.dart\nuploadFile]
        Prov_Batch[local_sync_provider.dart\nstartSync]
        
        API[api_service.dart\nAPI Client]

        UI_Import -- "Single File" --> Prov_Single
        UI_Import -- "Folder Sync" --> Prov_Batch
        
        Prov_Single -- "POST /upload" --> API
        Prov_Batch -- "POST /local-sync/sync" --> API
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_Upload[upload.py\nupload_statement_v2]
        Route_Sync[local_sync.py\nsync_folder]
        
        API --> Route_Upload
        API --> Route_Sync
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Task_Sync[local_sync_service.py\nscan_and_import]
        Route_Sync -- "Background Task" --> Task_Sync
        
        Srv_Parser[parser_service.py\nParserService.parse_statement]
        Route_Upload --> Srv_Parser
        Task_Sync --> Srv_Parser
        
        Srv_Acct[account_resolution_service.py\nAccountResolutionService.resolve_or_create]
        Route_Upload --> Srv_Acct
        Task_Sync --> Srv_Acct
        
        Srv_Audit[statement_audit_service.py\nStatementAuditService.save_statement]
        Route_Upload --> Srv_Audit
        Task_Sync --> Srv_Audit
        
        Srv_Tx[transaction_service.py\nUnifiedTransactionService.create_from_parsed]
        Srv_Audit --> Srv_Tx
    end

    %% Database
    subgraph DB [SQLite Database]
        DB_Bank[(bank_accounts)]
        DB_Audit[(statement_audit)]
        DB_Tx[(unified_transactions)]
        
        Srv_Acct -- "SELECT/INSERT" --> DB_Bank
        Srv_Audit -- "INSERT" --> DB_Audit
        Srv_Tx -- "INSERT (Batch)" --> DB_Tx
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef prov fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_Import ui;
    class Prov_Single,Prov_Batch prov;
    class API api;
    class Route_Upload,Route_Sync router;
    class Task_Sync,Srv_Parser,Srv_Acct,Srv_Audit,Srv_Tx service;
    class DB_Bank,DB_Audit,DB_Tx db;
```

---

## 2. Transaction Parsing & Categorization Flow

**Overview:** The core logic executed during an import to intelligently assign categories. It runs a waterfall of native heuristics (UPI, MCC, Regex) followed by user-defined custom Rules.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Entry Point
    subgraph Import Engine
        Srv_Tx[transaction_service.py\nUnifiedTransactionService.create_from_parsed]
    end

    %% Heuristics Engine
    subgraph Heuristics
        Srv_Cat[categorization_service.py\nauto_categorize]
        Match_UPI[_match_upi]
        Match_MCC[_match_mcc]
        Match_Regex[_match_regex]
        
        Srv_Tx --> Srv_Cat
        Srv_Cat --> Match_UPI
        Srv_Cat --> Match_MCC
        Srv_Cat --> Match_Regex
    end

    %% Rules Engine Fallback
    subgraph Rules Engine
        Srv_Rules[classification_rule_service.py\nClassificationRuleService.match_transaction]
        
        Srv_Tx -- "If confidence < 0.85" --> Srv_Rules
    end

    %% Thresholding
    subgraph Result Thresholding
        Decide{Confidence >= 0.85?}
        State_High[review_status = AUTO_PARSED\nBypasses Review]
        State_Low[review_status = NEEDS_REVIEW\ncategory_id = null]
        
        Srv_Cat --> Decide
        Srv_Rules --> Decide
        Decide -- Yes --> State_High
        Decide -- No --> State_Low
    end

    %% Styling
    classDef engine fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef rules fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef logic fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef state fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    class Srv_Tx,Srv_Cat,Match_UPI,Match_MCC,Match_Regex engine;
    class Srv_Rules rules;
    class Decide logic;
    class State_High,State_Low state;
```

---

## 3. Review & Classification Rules Flow

**Overview:** How users manually review low-confidence transactions and create global rules to automatically categorize them retroactively and in the future.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Review[review_screen.dart\nFilters: reviewStatus='NEEDS_REVIEW']
        UI_Dialog[ClassificationRuleDialog]
        
        UI_Review -- "Approve & Create Rule" --> UI_Dialog
        
        API_Client[classification_rules_api.dart\nAPI Client]
        UI_Dialog -- "POST /rules" --> API_Client
        UI_Dialog -- "POST /rules/{id}/apply" --> API_Client
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_Rules[classification_rules.py\napply_rule_endpoint]
        API_Client --> Route_Rules
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Srv_Rules[classification_rule_service.py\nClassificationRuleService.apply_rule]
        Route_Rules --> Srv_Rules
        
        Query_Tx[Fetch Transactions\ncategory_id IS NULL OR review_status = 'NEEDS_REVIEW']
        Srv_Rules --> Query_Tx
        
        Match_Pattern[Evaluate Pattern against\ndescription & merchant_name]
        Query_Tx --> Match_Pattern
        
        Update_State[Set review_status = 'REVIEWED'\nclassification_source = 'AUTO_RULE']
        Match_Pattern -- Match Found --> Update_State
    end

    %% Event Bus Sync
    subgraph State Sync [Riverpod Event Bus]
        Sync_Trigger[reviewRefreshTriggerProvider\nIncrements on success]
        Reload_UI[Reload Review Pane\nMatched items vanish]
        
        API_Client -- "Returns updated_count" --> Sync_Trigger
        Sync_Trigger --> Reload_UI
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef sync fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;

    class UI_Review,UI_Dialog ui;
    class API_Client api;
    class Route_Rules router;
    class Srv_Rules,Query_Tx,Match_Pattern,Update_State service;
    class Sync_Trigger,Reload_UI sync;
```

---

## 4. Transaction Browsing & Calendar Flow

**Overview:** How transactions are fetched, filtered, viewed on the calendar, and manually edited or deleted by the user across the app.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_List[Transaction Lists\ncalendar_screen, dashboard_widget, accounts_widget]
        UI_Edit[Inline Category Edit / Swipe to Delete]
        
        UI_List --> UI_Edit
        
        API_Client[transaction_api.dart\nAPI Client]
        UI_List -- "GET /transactions" --> API_Client
        UI_Edit -- "PATCH /transactions/{id}" --> API_Client
        UI_Edit -- "DELETE /transactions/{id}" --> API_Client
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_Get[unified_transactions.py\nlist_transactions]
        Route_Patch[unified_transactions.py\nupdate_transaction]
        Route_Delete[unified_transactions.py\ndelete_transaction]
        
        API_Client --> Route_Get
        API_Client --> Route_Patch
        API_Client --> Route_Delete
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Srv_Tx_Query[transaction_service.py\nUnifiedTransactionService.query]
        Route_Get --> Srv_Tx_Query
        
        Srv_Tx_Update[transaction_service.py\nUnifiedTransactionService.update_transaction]
        Route_Patch --> Srv_Tx_Update
        
        Update_State[Set classification_source = 'USER_DIRECT'\nconfidence = 1.0]
        Srv_Tx_Update --> Update_State
        
        Srv_Tx_Delete[transaction_service.py\nUnifiedTransactionService.delete_transaction]
        Route_Delete --> Srv_Tx_Delete
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;

    class UI_List,UI_Edit ui;
    class API_Client api;
    class Route_Get,Route_Patch,Route_Delete router;
    class Srv_Tx_Query,Srv_Tx_Update,Update_State,Srv_Tx_Delete service;
```

---

## 5. Account Management Flow

**Overview:** How bank accounts and credit cards are registered, linked to imported statements, merged when duplicates arise, and managed by the user.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_List[accounts_widget.dart\nListView of accounts]
        UI_Form[account_detail_screen.dart\nCreate/Edit/Merge]
        
        UI_List --> UI_Form
        
        API_Client[accounts_api.dart\nAPI Client]
        UI_List -- "GET /accounts/{id}/summary" --> API_Client
        UI_Form -- "POST /accounts" --> API_Client
        UI_Form -- "PUT /accounts/{id}" --> API_Client
        UI_Form -- "POST /accounts/merge" --> API_Client
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_Accounts[accounts.py\nAccounts Router]
        API_Client --> Route_Accounts
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Srv_Acct_Sum[accounts_service.py\nAccountsService.get_account_summary]
        Route_Accounts --> Srv_Acct_Sum
        
        Srv_Acct_Merge[accounts_service.py\nAccountsService.merge_accounts]
        Route_Accounts --> Srv_Acct_Merge
        
        Srv_Resolve[account_resolution_service.py\nAccountResolutionService.resolve_or_create]
    end

    %% Database
    subgraph DB [SQLite Database]
        DB_Bank[(bank_accounts)]
        DB_Tx[(unified_transactions)]
        DB_Audit[(statement_audit)]
        
        Srv_Acct_Sum -- "Read" --> DB_Bank
        Srv_Acct_Sum -- "Count" --> DB_Tx
        
        Srv_Acct_Merge -- "Reassign FK" --> DB_Tx
        Srv_Acct_Merge -- "Reassign FK" --> DB_Audit
        Srv_Acct_Merge -- "Soft Delete" --> DB_Bank
        
        Srv_Resolve -- "Create Dynamic" --> DB_Bank
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_List,UI_Form ui;
    class API_Client api;
    class Route_Accounts router;
    class Srv_Acct_Sum,Srv_Acct_Merge,Srv_Resolve service;
    class DB_Bank,DB_Tx,DB_Audit db;
```

---

## 6. Investments Tracking Flow

**Overview:** How investment transactions (MF, Stocks, PPF) are detected and aggregated into a live portfolio dashboard with asset class breakdowns.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Dash[investments_screen.dart\nDashboard]
        UI_Config[investment_settings_screen.dart\nRules Config]
        
        Prov_Dash[dashboard_provider.dart]
        Prov_Rules[investment_rules_provider.dart]
        
        UI_Dash --> Prov_Dash
        UI_Config --> Prov_Rules
        
        API_Client[API Client]
        Prov_Dash -- "GET /analytics/investments" --> API_Client
        Prov_Rules -- "GET/POST rules" --> API_Client
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_Analytics[analytics.py]
        Route_Rules[investment_rules.py]
        
        API_Client --> Route_Analytics
        API_Client --> Route_Rules
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Srv_Invest[analytics_service.py\nInvestmentAnalyticsService.get_analytics]
        Route_Analytics --> Srv_Invest
        
        Srv_Data[Fetch Active InvestmentRules\nMatch category_id / merchant regex]
        Srv_Invest --> Srv_Data
        
        Srv_Group[Group by Month: Velocity Trend\nGroup by AssetClass: Breakdown]
        Srv_Data --> Srv_Group
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef prov fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;

    class UI_Dash,UI_Config ui;
    class Prov_Dash,Prov_Rules prov;
    class API_Client api;
    class Route_Analytics,Route_Rules router;
    class Srv_Invest,Srv_Data,Srv_Group service;
```

---

## 7. Dashboard & Analytics Flow

**Overview:** View financial summary, charts, and insights. Dashboard layout is customizable.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Dash[Dashboard Widget\nTime Range Filter]
        UI_Tiles[Dashboard Tiles\nSummary, Breakdown, Trends, etc.]
        
        UI_Dash --> UI_Tiles
        
        API_Client[analytics_api.dart]
        UI_Tiles -- "GET /analytics/summary\nGET /analytics/spending-trends" --> API_Client
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_Analytic[analytics.py]
        API_Client --> Route_Analytic
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Srv_Analytic[analytics_service.py\nGenerates Aggregations]
        Route_Analytic --> Srv_Analytic
        
        Calc_Agg[Group by time, category, merchant]
        Srv_Analytic --> Calc_Agg
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;

    class UI_Dash,UI_Tiles ui;
    class API_Client api;
    class Route_Analytic router;
    class Srv_Analytic,Calc_Agg service;
```

---

## 8. Category Management Flow

**Overview:** Create, edit, and configure auto-categorization keywords.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Cat[Categories Settings\nList & Add Categories]
        API_Client[categories_api.dart]
        
        UI_Cat -- "GET / POST / PUT / DELETE" --> API_Client
    end

    %% Backend
    subgraph Routers [FastAPI Routers]
        Route_Cat[categories.py\nCRUD Endpoints]
        API_Client --> Route_Cat
    end

    subgraph Services [Backend Services]
        Srv_Cat[category_service.py\nManages Categories & Keywords]
        Route_Cat --> Srv_Cat
    end

    %% Database
    subgraph DB [SQLite Database]
        DB_Categories[(categories)]
        Srv_Cat -- "Read / Write" --> DB_Categories
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_Cat ui;
    class API_Client api;
    class Route_Cat router;
    class Srv_Cat service;
    class DB_Categories db;
```

---

## 9. App Settings, GDrive Backup & Data Management Flow

**Overview:** System administration tasks, including Google Drive backups, CSV exports, and database resetting.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Settings[settings_screen.dart]
        UI_DB[database_manager_screen.dart]
        
        API_Client[gdrive_api.dart]
        UI_Settings --> API_Client
        UI_DB --> API_Client
    end

    %% Backend Routers
    subgraph Routers [FastAPI Routers]
        Route_G[gdrive.py\nBackup endpoints]
        Route_Exp[export.py\nCSV/Clear-all]
        
        API_Client --> Route_G
        API_Client --> Route_Exp
    end

    %% Backend Services
    subgraph Services [Backend Services]
        Task_Backup[Create tar.gz\nUpload to GDrive via OAuth]
        Task_Export[Stream UnifiedTransaction rows as CSV]
        Task_Clear[db.query().delete() across core tables]
        
        Route_G --> Task_Backup
        Route_Exp --> Task_Export
        Route_Exp --> Task_Clear
    end

    %% Database
    subgraph DB [SQLite Database]
        DB_Bank[(bank_accounts)]
        DB_Tx[(unified_transactions)]
        DB_Audit[(statement_audit)]
        
        Task_Export -- "SELECT" --> DB_Tx
        Task_Clear -- "DELETE" --> DB_Bank
        Task_Clear -- "DELETE" --> DB_Tx
        Task_Clear -- "DELETE" --> DB_Audit
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_Settings,UI_DB ui;
    class API_Client api;
    class Route_G,Route_Exp router;
    class Task_Backup,Task_Export,Task_Clear service;
    class DB_Bank,DB_Tx,DB_Audit db;
```

---

## 10. UPI ID Management Flow

**Overview:** Map UPI handles to accounts and categories for smarter categorization.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_UPI[UPI Settings\nManage Own and Third-Party UPIs]
        API_Client[upi_api.dart]
        
        UI_UPI -- "GET / POST / PUT / DELETE" --> API_Client
    end

    %% Backend
    subgraph Routers [FastAPI Routers]
        Route_UPI[upi.py\nCRUD & Rescan Endpoints]
        API_Client --> Route_UPI
    end

    subgraph Services [Backend Services]
        Srv_UPI[upi_service.py]
        Srv_Tx[transaction_service.py\nApply Rules Retroactively]
        
        Route_UPI --> Srv_UPI
        Route_UPI -- "POST /rescan" --> Srv_Tx
    end

    %% Database
    subgraph DB [SQLite Database]
        DB_UPI[(upi_ids)]
        DB_Tx[(unified_transactions)]
        
        Srv_UPI -- "Read / Write" --> DB_UPI
        Srv_Tx -- "Update Categories" --> DB_Tx
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_UPI ui;
    class API_Client api;
    class Route_UPI router;
    class Srv_UPI,Srv_Tx service;
    class DB_UPI,DB_Tx db;
```

---

## 11. Local Directory Sync Flow

**Overview:** Scan and import bank statements from a local filesystem directory.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Sync[Import Screen\nSelect Folder]
        API_Client[local_sync_provider.dart]
        
        UI_Sync -- "Configure / Scan" --> API_Client
    end

    %% Backend
    subgraph Routers [FastAPI Routers]
        Route_Sync[local_sync.py]
        API_Client --> Route_Sync
    end

    subgraph Services [Backend Services]
        Task_Scan[local_sync_service.py\nscan_and_import]
        Srv_Parse[parser_service.py\nParse detected PDFs/CSVs]
        
        Route_Sync -- "Background Task" --> Task_Scan
        Task_Scan --> Srv_Parse
    end

    %% Database
    subgraph DB [SQLite Database]
        DB_Audit[(statement_audit)]
        DB_Tx[(unified_transactions)]
        
        Srv_Parse -- "INSERT" --> DB_Audit
        Srv_Parse -- "INSERT" --> DB_Tx
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef service fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_Sync ui;
    class API_Client api;
    class Route_Sync router;
    class Task_Scan,Srv_Parse service;
    class DB_Audit,DB_Tx db;
```

---

## 12. Admin / Database Manager Flow

**Overview:** Browse, search, and edit database tables through a generic admin interface.

#### Knowledge Graph Trace

```mermaid
graph TD
    %% Frontend UI
    subgraph Frontend [Flutter Frontend]
        UI_Admin[Database Manager\nTable Viewer]
        API_Client[admin_api.dart]
        
        UI_Admin -- "GET / PUT / DELETE rows" --> API_Client
    end

    %% Backend
    subgraph Routers [FastAPI Routers]
        Route_Admin[admin.py]
        API_Client --> Route_Admin
    end

    subgraph Database [SQLite Database]
        DB_All[(All core tables)]
        Route_Admin -- "Dynamic SQLAlchemy Queries" --> DB_All
    end

    %% Styling
    classDef ui fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef api fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef router fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;
    classDef db fill:#eceff1,stroke:#37474f,stroke-width:2px;

    class UI_Admin ui;
    class API_Client api;
    class Route_Admin router;
    class DB_All db;
```

---

## API Summary

| Domain | Endpoints | Version |
|--------|:---------:|---------|
| Health | 1 | — |
| Upload (Unified) | 3+ | v2 |
| Categories | 7+ | v2 |
| Unified Transactions | 8 | v2 |
| Tags | 4 | v2 |
| Analytics | 7 | v2 |
| Accounts | 4 | v2 |
| Export/Data | 3 | v2 |
| Google Drive (OAuth) | 12 | v2 |
| UPI IDs | 7 | v2 |
| Local Directory Sync | 6 | v2 |
| Admin / Database | 7+ | v2 |
| Classification Rules | 5 | v2 |

> All v2 endpoints are prefixed with `/api/v2/`.
> The `/health` endpoint is public; all others operate directly on the backend.
> Interactive API docs available at `/docs` (Swagger UI) and `/redoc` (ReDoc) when the backend is running.
