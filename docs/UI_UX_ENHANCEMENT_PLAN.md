# UI/UX Enhancement Plan — Finance Tracker v2

> **Current State:** Functional MVP with 3-tab layout (Upload, Savings, Credit Card), basic DataTable views, solid error handling. No charts, no dark mode, no state management, no responsive design.

---

## Phase 1: Foundation & Quick Wins (1-2 days)

These changes establish the architectural patterns needed for later phases and deliver immediate visible improvements.

### 1.1 State Management with Riverpod
**Why:** `setState()` doesn't scale. Uploading a statement on Tab 0 should auto-refresh transactions on Tabs 1/2. Riverpod enables shared state, caching, and reactive UI.

**Tasks:**
- [ ] Add `flutter_riverpod` dependency
- [ ] Create `StatementsNotifier` — holds upload state, exposes parsed results
- [ ] Create `TransactionsNotifier` — holds transaction list, date range, loading state
- [ ] Create `AppSettingsNotifier` — holds theme mode, base URL, preferences
- [ ] Wrap `FinanceTrackerApp` in `ProviderScope`
- [ ] Migrate `StatementUploadWidget` to use `ConsumerStatefulWidget`
- [ ] Migrate `TransactionListWidget` to use `ConsumerWidget`
- [ ] Auto-refresh transaction list after successful upload

**Files affected:** `main.dart`, all widgets, new `providers/` directory

### 1.2 Dark Mode Support
**Why:** Basic user expectation. Material 3 makes this easy.

**Tasks:**
- [ ] Define `lightTheme` and `darkTheme` in `theme.dart`
- [ ] Replace all hardcoded colors (`Colors.red.shade700`, `Colors.green.shade50`, etc.) with semantic theme colors (`colorScheme.error`, `colorScheme.surfaceContainerHighest`, etc.)
- [ ] Add theme toggle button in AppBar
- [ ] Persist theme preference with `shared_preferences`
- [ ] Use `colorScheme.primary` / `colorScheme.errorContainer` for transaction type badges

**Files affected:** `main.dart`, new `theme.dart`, all widgets

### 1.3 Date Range Filter
**Why:** Backend already supports `from` and `to` query params. Users need this to view transactions by period.

**Tasks:**
- [ ] Add a filter row above the DataTable with:
  - "From" date picker (`showDatePicker`)
  - "To" date picker
  - Quick presets: "Last 7 days", "Last 30 days", "Last 3 months", "This year", "All"
- [ ] Wire date params through `ApiService.getSavingsTransactions(from:, to:)`
- [ ] Show active filter as a `Chip` that can be cleared
- [ ] Default to "Last 30 days" with visible indicator

**Files affected:** `transaction_list_widget.dart`, `api_service.dart`

### 1.4 Fix Broken Test + Add Model Tests
**Why:** CI will fail; models are easy to test.

**Tasks:**
- [ ] Fix `widget_test.dart` to reference `FinanceTrackerApp`
- [ ] Add unit tests for `SavingsTransaction.fromJson`, `CreditCardTransaction.fromJson`
- [ ] Add unit tests for `_toDouble` edge cases (null, int, double, string, invalid)
- [ ] Add unit tests for `TransactionType.fromString`

**Files affected:** `test/`

---

## Phase 2: Dashboard & Data Visualization (2-3 days)

Transform the app from a "data viewer" into a "financial insights" tool.

### 2.1 Dashboard Screen (New Home Tab)
**Why:** First thing users see should be a summary, not an upload form.

**Tasks:**
- [ ] Create `DashboardScreen` as the new first tab
- [ ] Add summary cards:
  - Total Credits / Total Debits / Net (current month)
  - Savings Account Balance (latest closing balance)
  - Credit Card Total Dues / Min Due / Available Credit
  - Number of transactions this month
- [ ] Add month selector to switch between months
- [ ] Reorder tabs: Dashboard → Upload → Savings → Credit Card

**Components:**
```
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Total Income │ │ Total Spent  │ │  Net Balance  │
│   ₹45,200    │ │   ₹32,150    │ │   +₹13,050   │
└──────────────┘ └──────────────┘ └──────────────┘

┌────────────────────────────────────────────────┐
│        Spending Over Time (Line Chart)          │
│    ₹ ──────────────────                        │
│     /\    /\      ────                          │
│    /  \  /  \   /                               │
│   /    \/    \/                                  │
│   Jun   Jul   Aug   Sep   Oct                   │
└────────────────────────────────────────────────┘

┌──────────────────────┐ ┌──────────────────────┐
│ Recent Transactions  │ │ Credit Card Summary  │
│ • Amazon  -₹1,469   │ │ Dues: ₹508.00        │
│ • Swiggy  -₹282     │ │ Min:  ₹7.00          │
│ • Cred    -₹929     │ │ Limit: ₹2,00,000     │
└──────────────────────┘ └──────────────────────┘
```

### 2.2 Charts with fl_chart
**Why:** Visual spending trends are the core value of a finance tracker.

**Tasks:**
- [ ] Add `fl_chart` dependency
- [ ] **Line Chart:** Daily/weekly spending trend over selected period
- [ ] **Bar Chart:** Monthly credit vs debit comparison  
- [ ] **Pie/Donut Chart:** Spending by merchant category (derived from description keywords)
- [ ] Make charts responsive (resize with window)
- [ ] Add chart interactivity (tap for details, hover tooltips on web)

### 2.3 Transaction Search
**Why:** Users need to find specific transactions quickly.

**Tasks:**
- [ ] Add `SearchBar` widget above transaction table
- [ ] Client-side filtering by description (instant, no API call)
- [ ] Highlight matched text in results
- [ ] Show "X of Y transactions" count
- [ ] Add search icon in tab header for quick access

---

## Phase 3: Responsive Design & Navigation (1-2 days)

Make the app work well on different screen sizes (desktop, tablet, mobile web).

### 3.1 Responsive Layout
**Why:** Flutter Web users may access on any screen size.

**Tasks:**
- [ ] Define breakpoints: mobile (<600px), tablet (600-1024px), desktop (>1024px)
- [ ] **Mobile:** Bottom navigation bar with 4 tabs, full-width cards
- [ ] **Tablet:** Side navigation rail + content area
- [ ] **Desktop:** Side navigation drawer (collapsible) + wide content with 2-column layout
- [ ] Use `LayoutBuilder` / `MediaQuery` for adaptive layouts
- [ ] Transaction list: DataTable on desktop, Card-based list on mobile

### 3.2 Navigation with GoRouter
**Why:** URL-based routing is essential for web (bookmarkable, back button support).

**Tasks:**
- [ ] Add `go_router` dependency
- [ ] Define routes: `/`, `/upload`, `/savings`, `/credit-card`, `/settings`
- [ ] Support deep linking (share a URL to the credit card tab)
- [ ] Add browser back/forward button support
- [ ] Add 404 page for unknown routes

### 3.3 Improved Upload UX
**Why:** Upload is the primary action; it should feel premium.

**Tasks:**
- [ ] Drag-and-drop file zone (using `desktop_drop` or raw `Listener` on web)
- [ ] Upload progress indicator (determinate progress bar)
- [ ] File preview before upload (show filename, size, PDF icon)
- [ ] Upload history section (list of previously uploaded statements)
- [ ] Auto-detect bank type from PDF content (stretch goal)

---

## Phase 4: Polish & Micro-interactions (1-2 days)

Make the app feel professional and delightful.

### 4.1 Animations & Transitions
**Tasks:**
- [ ] Tab switch: fade + slide transition
- [ ] Transaction list loading: skeleton shimmer placeholders
- [ ] Upload success: animated checkmark (Lottie or custom `AnimatedIcon`)
- [ ] Card entrance: staggered fade-in for dashboard cards
- [ ] Sort change: `AnimatedSwitcher` on column headers
- [ ] Error state: shake animation on error card

### 4.2 Empty States
**Why:** New users see blank screens. Empty states guide them.

**Tasks:**
- [ ] Savings tab (no data): illustration + "Upload your first bank statement to see transactions here" + upload button
- [ ] Credit card tab (no data): Same pattern with credit card context
- [ ] Dashboard (no data): Onboarding card with step-by-step guide
- [ ] Search with no results: "No transactions match your search" with suggestion to clear filters

### 4.3 Toast Notifications → Rich Notifications
**Tasks:**
- [ ] Replace `SnackBar` with custom notification banner (top-aligned, auto-dismiss)
- [ ] Differentiate: success (green), warning (amber), error (red), info (blue)
- [ ] Add undo action on save operations ("Statement saved • UNDO")
- [ ] Group notifications if multiple arrive quickly

### 4.4 Transaction Details
**Tasks:**
- [ ] Tap a transaction row → slide-in detail panel (side sheet on desktop, bottom sheet on mobile)
- [ ] Show all fields: date, description, reference, amount, type, closing balance, statement it belongs to
- [ ] Add copy-to-clipboard on reference number
- [ ] Show related transactions (same merchant) — stretch goal

---

## Phase 5: Advanced Features (3-5 days)

Features that add significant value but require backend changes too.

### 5.1 Export to CSV/Excel
**Tasks:**
- [ ] Add export button on transaction lists
- [ ] Generate CSV with all visible columns (client-side using `csv` package)
- [ ] Trigger browser download via `dart:html` `AnchorElement`
- [ ] Filter-aware export (only export filtered/date-range transactions)

### 5.2 Category Tagging
**Tasks:**
- [ ] Backend: Add `category` field to transaction models (nullable)
- [ ] Auto-categorize based on description keywords (e.g., "AMAZON" → Shopping, "SWIGGY" → Food & Dining)
- [ ] Category management screen (add/edit/delete categories)
- [ ] Category color coding in transaction list
- [ ] Category breakdown in dashboard charts

### 5.3 Statement History
**Tasks:**
- [ ] Backend: Add endpoint to list all uploaded statements
- [ ] Frontend: New "History" section showing all uploaded statements with metadata
- [ ] Allow re-viewing parsed details of any past statement
- [ ] Delete statement (with confirmation dialog)

### 5.4 Settings Screen
**Tasks:**
- [ ] Theme preference (light/dark/system)
- [ ] Backend URL configuration
- [ ] Default date range preference
- [ ] Currency symbol preference (₹, $, €)
- [ ] Clear local data / reset database

### 5.5 Pagination & Virtual Scrolling
**Tasks:**
- [ ] Backend: Add `?page=1&size=50` support to transaction endpoints
- [ ] Frontend: Paginated DataTable (page size selector: 25/50/100)
- [ ] "Load more" infinite scroll option for mobile view
- [ ] Show total count from backend

---

## Priority Matrix

| Phase | Effort | Impact | Recommendation |
|-------|--------|--------|----------------|
| Phase 1: Foundation | 1-2 days | High | **Do first** — enables everything else |
| Phase 2: Dashboard | 2-3 days | Very High | **Do second** — biggest user value |
| Phase 3: Responsive | 1-2 days | Medium | Do after Phase 2 |
| Phase 4: Polish | 1-2 days | Medium | Do after Phase 3 |
| Phase 5: Advanced | 3-5 days | High | Do incrementally after core is polished |

---

## Recommended New Dependencies

| Package | Purpose | Phase |
|---------|---------|-------|
| `flutter_riverpod` | State management | 1 |
| `shared_preferences` | Persist settings | 1 |
| `fl_chart` | Charts and graphs | 2 |
| `go_router` | URL-based routing | 3 |
| `shimmer` | Loading placeholders | 4 |
| `csv` | CSV export | 5 |
| `intl` | (already added) Date/currency formatting | — |

---

## Design Principles

1. **Progressive disclosure** — Show summary first, details on demand
2. **Immediate feedback** — Every action shows instant visual response
3. **Error prevention** — Validate early, guide users before they make mistakes
4. **Consistency** — Use Material 3 components and semantic colors everywhere
5. **Performance** — Paginate large datasets, cache API responses, lazy-load charts

---

## Current vs Target Comparison

| Aspect | Current | Target |
|--------|---------|--------|
| First impression | Upload form | Dashboard with financial summary |
| Theme | Light only | Light + Dark + System |
| Navigation | Flat 3-tab | Adaptive (bottom bar/rail/drawer) + URL routing |
| Data display | Raw DataTable | Sortable/filterable table + cards on mobile |
| Visualization | None | Line/bar/pie charts |
| Search | None | Instant client-side search |
| Date filtering | None | Date pickers + quick presets |
| Upload UX | Click to pick file | Drag-and-drop + progress + history |
| Empty states | Blank screen | Guided onboarding |
| State sharing | None (tab-local) | Cross-tab reactive state |
| Responsiveness | Fixed ~600px card | Mobile/tablet/desktop adaptive |
| Testing | Broken default test | Unit + widget + integration tests |
