# Finance Tracker v2 — Architecture Diagrams

Visual architecture reference for the full-stack application.

---

## 1. High-Level System Architecture

```mermaid
graph TB
    subgraph Client["Frontend — Flutter 3.x"]
        UI["Material Design 3 UI"]
        Router["GoRouter<br/>(6 nav destinations)"]
        Providers["Riverpod Providers<br/>(10 notifiers)"]
        AuthSvc["Auth Service<br/>(JWT token mgmt)"]
        ApiSvc["API Service<br/>(HTTP client)"]

        UI --> Router
        UI --> Providers
        Providers --> ApiSvc
        AuthSvc --> ApiSvc
    end

    subgraph Server["Backend — FastAPI 0.115"]
        Auth["Auth Module<br/>(JWT + bcrypt)"]
        Routers["16 Router Modules<br/>(81 endpoints)"]
        Services["15 Service Classes<br/>(business logic)"]
        Parsers["Parser Registry<br/>(PDF/CSV/LLM)"]
        Models["SQLAlchemy Models<br/>(13 tables)"]

        Auth --> Routers
        Routers --> Services
        Services --> Models
        Services --> Parsers
    end

    subgraph Storage["Data Layer"]
        SQLite[("SQLite DB<br/>(WAL mode)")]
        CredFile["Credentials JSON<br/>(.credentials.json)"]
        SyncState["Sync State JSON<br/>(.gdrive_sync_state.json)"]
    end

    subgraph External["External Services"]
        GDrive["Google Drive API"]
        Gemini["Google Gemini<br/>(LLM)"]
        Ollama["Ollama<br/>(local LLM)"]
    end

    ApiSvc -- "REST JSON<br/>+ Bearer Token" --> Auth
    Models --> SQLite
    Auth --> CredFile
    Services --> SyncState
    Services --> GDrive
    Parsers --> Gemini
    Parsers --> Ollama
```

---

## 2. Backend Layered Architecture

```mermaid
graph TB
    subgraph Presentation["Router Layer (API)"]
        direction LR
        R1["health.py"]
        R2["auth (auth.py)"]
        R3["upload.py"]
        R4["unified_transactions.py"]
        R5["categories.py"]
        R6["tags.py"]
        R7["analytics.py"]
        R8["accounts.py"]
        R9["budgets.py"]
        R10["goals.py"]
        R11["reminders.py"]
        R12["export.py"]
        R13["gdrive.py"]
        R14["transfers.py"]
        R15["upi.py"]
        R16["transactions.py<br/>(legacy)"]
    end

    subgraph Business["Service Layer"]
        direction LR
        S1["ParserService"]
        S2["TransactionService"]
        S3["CategoryService"]
        S4["CategorizationService"]
        S5["AnalyticsService"]
        S6["AccountsService"]
        S7["BudgetService"]
        S8["GoalsService"]
        S9["BillReminderService"]
        S10["RecurringService"]
        S11["GDriveSyncService"]
        S12["CreditCardService"]
        S13["SavingsService"]
        S14["TransferDetectionService"]
        S15["UpiService"]
    end

    subgraph Data["Model Layer"]
        direction LR
        M1["UnifiedTransaction"]
        M2["Category / CategoryKeyword"]
        M3["Tag / TransactionTag"]
        M4["Budget"]
        M5["SavingsGoal"]
        M6["BillReminder"]
        M7["RecurringTransaction"]
        M8["CreditCardStatement<br/>CreditCardTransaction"]
        M9["SavingsAccountStatement<br/>SavingsAccountTransaction"]
        M10["UpiId"]
    end

    Presentation --> Business
    Business --> Data
```

---

## 3. Request Flow (Authentication)

```mermaid
sequenceDiagram
    participant U as Flutter App
    participant A as Auth Module
    participant R as Protected Router
    participant S as Service Layer
    participant DB as SQLite

    Note over U,DB: First-time Registration
    U->>A: POST /api/auth/register {username, password}
    A->>A: Hash password (bcrypt)
    A->>A: Save to .credentials.json
    A->>A: Create JWT (HS256)
    A-->>U: {access_token, expires_in}
    U->>U: Store token (SharedPreferences)

    Note over U,DB: Subsequent API Calls
    U->>R: GET /api/v2/transactions<br/>Authorization: Bearer <token>
    R->>A: get_current_user(token)
    A->>A: Decode JWT, verify user
    A-->>R: username
    R->>S: TransactionService.query(...)
    S->>DB: SELECT FROM unified_transactions
    DB-->>S: rows
    S-->>R: [UnifiedTransaction, ...]
    R-->>U: JSON response
```

---

## 4. Statement Upload & Processing Pipeline

```mermaid
flowchart TD
    A[User uploads PDF/CSV] --> B{File type?}
    B -->|PDF| C[ParserRegistry lookup<br/>bank + statement_type]
    B -->|CSV| D[CSV Parser<br/>auto-detect columns]

    C --> F[Generic PDF Parser<br/>Table extraction + Text fallback]

    F --> E{Transactions<br/>found?}
    E -->|Yes| J[Parsed Statement Object]
    E -->|No| G{LLM enabled?}
    G -->|Yes| H[LLM Parser<br/>Gemini / Ollama]
    G -->|No| I[Error: No parser]

    H --> J
    D --> J

    J --> K[Save Raw Statement<br/>CC or Savings table]
    K --> L[Create UnifiedTransactions<br/>denormalized rows]
    L --> M[Auto-Categorize<br/>keyword matching]
    M --> N[Normalize Merchant Names<br/>strip UPI/NEFT/IMPS prefixes]
    N --> O[Done ✓]

    style A fill:#e1f5fe
    style O fill:#e8f5e9
    style I fill:#ffebee
```

---

## 5. Google Drive Sync Flow

```mermaid
flowchart TD
    A[User triggers sync<br/>POST /api/v2/gdrive/sync] --> B[Load sync state<br/>.gdrive_sync_state.json]
    B --> C[List files in<br/>Drive folder]
    C --> D{For each file}

    D --> E{Already processed?}
    E -->|Yes & !force| F[Skip]
    E -->|No or force| G[Download file content]

    G --> H[Infer bank + type<br/>from filename]
    H --> I{CSV or PDF?}

    I -->|CSV| J[CSV Parser]
    I -->|PDF| K[ParserService<br/>regex → LLM fallback]

    J --> L{Parse success?}
    K --> L

    L -->|Yes| M[Save statement + transactions]
    L -->|No| N[Mark as failed]

    M --> O[Mark file as processed<br/>in sync state]

    F --> P[Next file]
    O --> P
    N --> P

    P --> D
    D -->|All done| Q[Save sync state<br/>return summary]

    style A fill:#e1f5fe
    style Q fill:#e8f5e9
```

---

## 6. Database Entity Relationship Diagram

```mermaid
erDiagram
    credit_card_statements ||--o{ credit_card_transactions : "has many"
    savings_account_statements ||--o{ savings_account_transactions : "has many"

    categories ||--o{ category_keywords : "has many"
    categories ||--o{ categories : "parent_id (self)"
    categories ||--o{ unified_transactions : "categorizes"
    categories ||--o{ budgets : "budget per category"
    categories ||--o{ bill_reminders : "optional category"
    categories ||--o{ recurring_transactions : "optional category"

    unified_transactions }o--o{ tags : "many-to-many via transaction_tags"

    credit_card_statements {
        int id PK
        date statement_date
        date due_date
        string card_number
        string card_holder_name
        decimal credit_limit
        decimal total_dues
    }

    credit_card_transactions {
        int id PK
        date date
        string description
        decimal amount
        enum type "CREDIT/DEBIT"
        int statement_id FK
    }

    savings_account_statements {
        int id PK
        string account_number
        string account_holder_name
        date from_date
        date to_date
        decimal opening_balance
        decimal closing_balance
    }

    savings_account_transactions {
        int id PK
        date date
        string description
        decimal withdrawal_amount
        decimal deposit_amount
        decimal closing_balance
        enum type "CREDIT/DEBIT"
        int statement_id FK
    }

    unified_transactions {
        int id PK
        date date
        string description
        decimal amount
        enum type "CREDIT/DEBIT"
        enum source_type "SAVINGS/CREDIT_CARD"
        int source_transaction_id
        string bank
        int category_id FK
        string merchant_name
        bool is_transfer
        string transfer_group_id
        enum transfer_type "INTERNAL_TRANSFER/CC_BILL_PAYMENT"
        datetime created_at
    }

    categories {
        int id PK
        string name UK
        string icon
        string color
        int parent_id FK
        bool is_system
    }

    category_keywords {
        int id PK
        string keyword UK
        int category_id FK
    }

    tags {
        int id PK
        string name UK
        string color
    }

    transaction_tags {
        int transaction_id PK_FK
        int tag_id PK_FK
    }

    budgets {
        int id PK
        int category_id FK
        int year
        int month
        decimal amount
        bool rollover
    }

    savings_goals {
        int id PK
        string name
        decimal target_amount
        decimal current_amount
        date deadline
        bool is_completed
    }

    bill_reminders {
        int id PK
        string name
        decimal amount
        int category_id FK
        bool is_recurring
        string frequency
        date next_due_date
    }

    recurring_transactions {
        int id PK
        string merchant_name
        decimal average_amount
        string frequency
        int category_id FK
        date next_expected_date
        bool is_subscription
    }

    upi_ids {
        int id PK
        string upi_handle UK
        string label
        string account_type
        string account_identifier
        int category_id FK
        bool is_own
        datetime created_at
    }

    categories ||--o{ upi_ids : "optional category"
```

---

## 7. Frontend Widget & Provider Architecture

```mermaid
graph TB
    subgraph EntryPoint["App Entry"]
        Main["main.dart<br/>ProviderScope + MaterialApp.router"]
    end

    subgraph Auth["Authentication Layer"]
        AuthProv["AuthNotifier<br/>(authProvider)"]
        LoginScr["LoginScreen"]
        AuthSvc["AuthService<br/>(JWT management)"]
    end

    subgraph Shell["App Shell"]
        AppShell["AppShell<br/>(responsive layout)"]
        GoRouter["GoRouter<br/>(6 nav destinations)"]
    end

    subgraph Screens["Screens & Widgets"]
        Dashboard["DashboardWidget<br/>charts + summary"]
        Upload["StatementUploadWidget<br/>drag-drop + bank selector"]
        Calendar["CalendarScreen<br/>spending heatmap + editable transactions"]
        Accounts["AccountsWidget<br/>account cards + inline transaction list"]
        Budget["BudgetGoalsWidget<br/>budgets + goals + reminders"]
        UpiMgmt["UpiManagementWidget<br/>UPI handle mappings"]
        Settings["SettingsScreen<br/>theme + currency + URL"]
    end

    subgraph Providers["Riverpod State Management"]
        AppSettings["AppSettingsNotifier<br/>(theme, currency, URL)"]
        DashProv["DashboardNotifier<br/>(analytics data)"]
        TxnProv["UnifiedTransactionsNotifier<br/>(filters, pagination)"]
        CatProv["CategoriesNotifier<br/>(categories + tags)"]
        AccProv["AccountsNotifier<br/>(accounts + statements)"]
        BudProv["BudgetNotifier<br/>(budgets, goals, reminders)"]
        StmtProv["StatementsNotifier<br/>(upload state)"]
        XferProv["TransfersNotifier<br/>(transfer pairs)"]
        UpiProv["UpiNotifier<br/>(UPI mappings)"]
    end

    subgraph API["API Layer"]
        ApiService["ApiService<br/>(static HTTP client)"]
    end

    Main --> AuthProv
    AuthProv -->|authenticated| AppShell
    AuthProv -->|unauthenticated| LoginScr
    LoginScr --> AuthSvc
    AuthSvc --> ApiService

    AppShell --> GoRouter
    GoRouter --> Screens

    Dashboard --> DashProv
    Upload --> StmtProv
    Calendar --> DashProv
    Calendar --> CatProv
    Accounts --> AccProv
    Accounts --> TxnProv
    Budget --> BudProv
    UpiMgmt --> UpiProv
    UpiMgmt --> CatProv
    Settings --> AppSettings

    Providers --> ApiService
    ApiService -- "HTTP + JWT" --> Backend["FastAPI Backend"]
```

---

## 8. Deployment Architecture (Docker)

```mermaid
graph LR
    subgraph Docker["Docker Compose"]
        subgraph FE["frontend container<br/>(port 3000)"]
            Nginx["nginx"]
            FlutterBuild["Flutter Web Build<br/>(static files)"]
            Nginx --> FlutterBuild
        end

        subgraph BE["backend container<br/>(port 8080)"]
            Uvicorn["Uvicorn ASGI"]
            FastAPI["FastAPI App"]
            Uvicorn --> FastAPI
        end

        subgraph Vol["Named Volume"]
            Data[("finance-data<br/>/app/data/")]
        end

        FE -- "proxy API calls" --> BE
        BE --> Data
    end

    Browser["Browser / Desktop"] -- "HTTP :3000" --> Nginx
    Browser -- "HTTP :8080<br/>(direct API)" --> Uvicorn

    style Docker fill:#f5f5f5,stroke:#333
```

---

## 9. Auto-Categorization Pipeline

```mermaid
flowchart LR
    A["Transaction<br/>Description"] --> B["Normalize<br/>(lowercase, strip)"]
    B --> C["Match against<br/>category keywords"]
    C --> D{Match found?}
    D -->|Yes| E["Assign category<br/>(longest match wins)"]
    D -->|No| F["Assign 'Other'<br/>category"]

    G["Transaction<br/>Description"] --> H["Strip UPI/NEFT/IMPS<br/>prefixes"]
    H --> I["Remove reference<br/>numbers & dates"]
    I --> J["Title Case<br/>cleanup"]
    J --> K["Store as<br/>merchant_name"]

    style E fill:#e8f5e9
    style F fill:#fff3e0
```

---

## 10. Navigation & Responsive Layout

```mermaid
graph TD
    subgraph Mobile["< 600px — Mobile"]
        MobileNav["Bottom NavigationBar"]
        MobileContent["Full-width content"]
        MobileNav --> MobileContent
    end

    subgraph Tablet["600–899px — Tablet"]
        TabletRail["Compact NavigationRail<br/>(icons only)"]
        TabletContent["Content area"]
        TabletRail --> TabletContent
    end

    subgraph Desktop["≥ 900px — Desktop"]
        DesktopRail["Expanded NavigationRail<br/>(sidebar, 220px, labels)"]
        DesktopContent["Wide content area"]
        DesktopRail --> DesktopContent
    end

    LayoutBuilder["LayoutBuilder<br/>(checks width)"] --> Mobile
    LayoutBuilder --> Tablet
    LayoutBuilder --> Desktop
```
