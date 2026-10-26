# Alfa Mart – Cash Flow & Accounts (Flutter)

Offline-first Android app for the Alfa Mart admin and managers to record and
check the daily cash flow of every counter and cashier.

**Install:** download `release/AlfaMart-CashFlow.apk` to the phone and open it
(allow "Install unknown apps" when Android asks). For old 32-bit phones use
`release/AlfaMart-CashFlow-older-phones.apk`. Requires Android 7.0 or newer.

## Features

| Requirement | Where in the app |
|---|---|
| Works without internet | All data lives in a local SQLite database on the phone |
| Login + fingerprint login | First launch creates the Admin. Fingerprint is turned on in *More → Security* |
| 2 counters (more can be added) | *More → Counters & Cashiers* (Counter 1 and Counter 2 are created automatically) |
| Several cashiers per counter, shift by shift | Each **Shift Sale** stores the date, counter, cashier and duty start/end time |
| Daily sale per counter / cashier | *Add Entry → Shift Sale* |
| 4 payment methods | Cash, POS Machine, Online Banking, JazzCash on every shift |
| Daily purchases | *Add Entry → Purchase* (supplier, invoice #, paid by) |
| Cash the purchaser takes from a cashier | *Add Entry → Cash to Purchaser* (who, from which cashier/counter, amount, purpose) |
| Expenses per counter / cashier with details | *Add Entry → Expense* (category, counter, cashier, paid by, details) |
| Dashboard filters | 24 Hours, 1 Week, 1 Month, 3 Months, 6 Months, 12 Months, Custom range, per counter |
| Tiles | Sales, Purchase, Expense, Net Cash Flow, Cash to Purchaser, Cash Short/Excess |
| Excel export (admin) | *More → Export to Excel* |

### Cash checking (reconciliation)

For every shift the app works out how much cash **should** be in the drawer:

```
Expected cash = Opening cash + Cash sales − Cash given to purchaser − Cash expenses from the drawer
```

When the manager enters the **counted cash** at hand-over, the app shows the
cashier as *Balanced*, *Short* or *Excess* and asks for confirmation before
saving a mismatch. The dashboard adds up all shortages/excesses for the period.

### Excel workbook

The export contains these sheets, **all linked with live formulas** – change any
amount in Excel and every total, the Daily sheet and the Summary page update:

* **Summary** – overview, sales by payment method per counter, counter summary,
  cashier summary, purchases by method, expenses by category.
* **Daily** – day by day sales per counter, purchases, expenses, net cash flow.
* **Counter 1, Counter 2, …** – every shift (sorted by cashier) with the cash
  reconciliation columns, plus a cashier-wise summary table (Cashier 1,
  Cashier 2, …) on the right.
* **Purchases**, **Cash to Purchaser**, **Expenses** – the raw entries.

The workbook is plain `.xlsx` with formulas (no VBA macros), so it opens safely
in Excel, Google Sheets, WPS and LibreOffice and still recalculates
automatically. New rows can be added under the existing ones (up to row 5000).

### Safety for payments

* Money is stored as whole paisa (integers) – no rounding errors.
* Passwords: salted PBKDF2-SHA256; 5 wrong attempts lock the account for 5 min.
* Auto logout after 5 minutes in the background.
* Roles: **Admin** (everything) and **Manager** (enter/edit data, dashboard).
  Only admins can delete entries, export, manage users, view the audit log and
  backup/restore.
* Every create / edit / delete / login is written to the **Audit Log** with the
  before and after values. Deleted entries are hidden, never erased.
* Duplicate shift warning and amount validation on every form.
* *Backup & Restore*: share the whole database to Drive/WhatsApp/email and
  restore it on any phone. Android cloud auto-backup is disabled on purpose so
  the data never leaves the phone without the admin's action.

## Online later (server)

The app is offline-first and already prepared for a server:

* Every record has a UUID, `created_at/updated_at`, `created_by/updated_by`,
  `is_deleted` and `sync_status` columns.
* `lib/sync/remote_api.dart` defines the contract a server must implement
  (push changed rows / pull rows changed since a time per table).
* `lib/sync/sync_service.dart` already does two-way, last-write-wins sync.
* To go online, implement `RemoteApi` (e.g. with `package:http`) and replace
  `OfflineRemoteApi()` in `lib/app.dart`. No other code needs to change.

## Project structure

```
lib/
  core/          theme, money, dates/periods, enums, password hashing
  data/          SQLite schema (app_database.dart), models, generic repository + audit
  services/      auth, fingerprint, reports (dashboard maths), Excel writer/export, backup
  sync/          server contract + sync engine
  ui/            screens, entry forms, shared widgets
assets/images/   logo, icon, splash
```

## Building

```bash
flutter pub get
flutter test                     # includes an end-to-end UI test (test/app_flow_test.dart)
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Regenerate icons / splash after changing the images:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

GitHub Actions (`.github/workflows/build-apk.yml`) builds the APK on every push
to `main` and attaches it to the run as an artifact.

### Signing

Without `android/key.properties` the release APK is signed with a debug key.
Before publishing (or before handing out updates from a different computer),
create your own keystore and `android/key.properties`:

```
storeFile=/path/to/alfamart.jks
storePassword=...
keyAlias=alfamart
keyPassword=...
```

Android only installs an update over an app signed with the same key. If the key
changes the old app must be uninstalled, which deletes its data, so **take a
backup first** (More → Backup & Restore).
