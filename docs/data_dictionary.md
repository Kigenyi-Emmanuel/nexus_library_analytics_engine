# Data Dictionary — Nexus Library Analytics Engine

## 1. Purpose and scope

This document defines the business meaning and intended analytical use of the data entities documented for the **Nexus Library Analytics Engine**, a portfolio project using synthetic library data, PostgreSQL, and Power BI.

This first version is based on the fields and relationships described in the repository README. The README does not include the complete PostgreSQL table definitions, so physical data types, nullability, defaults, indexes, and all constraints must be confirmed against the implemented schema before this document is treated as a definitive schema specification.

## 2. Data source

- **Source:** Synthetically engineered data representing library membership, catalog inventory, borrowing transactions, fine accruals, and fine payments.
- **Database:** PostgreSQL.
- **Reporting:** Power BI.
- **Payment context:** The project models payment records in an eCitizen-style collection process. Unless a live integration has actually been implemented and verified, describe eCitizen as a modeled or intended integration—not a live connection.
- **Privacy:** Use synthetic contact details only. Phone-number masking is a privacy control, but masking alone does not establish compliance with the Kenya Data Protection Act, 2019.

## 3. Entity overview

| Entity | Role | Documented primary key | Purpose |
|---|---|---|---|
| `members` | Dimension / master data | `member_id` | Stores member details, category, contact information, and join date. |
| `books` | Catalog dimension | `book_id` | Stores title, author, and library category/section. |
| `inventory_items` | Physical inventory | `copy_id` | Represents individual physical copies and their operational status. |
| `borrowing_transactions` | Circulation fact | `transaction_id` | Records borrowing events, due/return dates, and fine accruals. |
| `fine_payments` | Payment fact | `payment_id` | Records payments applied to borrowing transactions, including partial payments. |

**Modeling note:** The README describes the design as a star schema, but the documented structure is a normalized relational model. Describe it as a normalized PostgreSQL model unless the implemented reporting model has been verified as a star schema.

## 4. Field-level dictionary

### 4.1 `members`

| Field | Business meaning | Intended use and notes |
|---|---|---|
| `member_id` | Unique identifier for a library member. | Primary key; connects members to borrowing transactions. |
| `full_name` | Member's name. | Direct personal identifier. Restrict access and avoid exposing it unnecessarily in public-facing reports. |
| `phone_number` | Member's original phone number. | Personal contact information. Keep access restricted; do not expose it in public report visuals or sample data. |
| `masked_phone` | Transformed representation of the phone number. | Use where contact identification is not required. Confirm that the masking transformation and stored value are consistent. |
| `category` | Member group, such as Children, Adults, Students, or Researchers. | Supports membership segmentation. Confirm allowed values in the source data. |
| `join_date` | Date the member joined the library. | Supports membership growth and cohort/time analysis. |

**Implementation check:** The README shows a query deriving `masked_phone` from `phone_number`, while the analytical view reads `m.masked_phone`. Confirm that the column is populated consistently or generate the masked value in a controlled transformation/view. Never publish real member contact details.

### 4.2 `books`

| Field | Business meaning | Intended use and notes |
|---|---|---|
| `book_id` | Unique identifier for a catalog title/record. | Primary key; referenced by physical inventory copies. |
| `title` | Title of the book. | Used for title-level circulation and inventory reporting. |
| `author` | Author or credited creator. | Catalog description and optional grouping. |
| `category_section` | Library section or catalog category. | Supports category-level utilization and procurement analysis. Confirm standardized values. |

### 4.3 `inventory_items`

| Field | Business meaning | Intended use and notes |
|---|---|---|
| `copy_id` | Unique identifier for an individual physical copy. | Primary key; referenced by borrowing transactions. |
| `book_id` | Catalog identifier for the title represented by the copy. | Foreign key to `books.book_id`. |
| `status` | Current operational state of the physical copy. | README lists Available, Borrowed, Maintenance, and Lost. Confirm actual permitted values and whether this is current-state or historical data. |

**Metric note:** Calculate inventory status counts from `inventory_items` at copy level. Avoid counting a copy multiple times because it appears in multiple historical borrowing transactions.

### 4.4 `borrowing_transactions`

| Field | Business meaning | Intended use and notes |
|---|---|---|
| `transaction_id` | Unique identifier for a borrowing event. | Primary key; identifies a distinct circulation transaction. |
| `copy_id` | Physical copy involved in the borrowing event. | Foreign key to `inventory_items.copy_id`. |
| `member_id` | Member who borrowed the copy. | Foreign key to `members.member_id`. |
| `issue_date` | Date the copy was issued. | Supports borrowing trends and circulation analysis. |
| `due_date` | Date the copy was due back. | Supports overdue analysis when compared with return date and the reporting date. |
| `return_date` | Date the copy was returned. | The README treats a null value as an active/unreturned borrowing record. Validate this meaning against the implemented data. |
| `fine_amount` | Fine amount accrued for the borrowing transaction. | Used to measure fine accruals. Confirm currency, numeric precision, and whether zero and null have distinct meanings. |

**Metric note:** A count of current unreturned transactions is not automatically the number of copies currently borrowed. For inventory utilization, count distinct copies currently on loan and divide by a clearly defined eligible inventory denominator. Ensure historical open transactions cannot double-count the same copy.

### 4.5 `fine_payments`

| Field | Business meaning | Intended use and notes |
|---|---|---|
| `payment_id` | Unique identifier for a payment record. | Primary key; supports payment-level traceability. |
| `transaction_id` | Borrowing transaction to which the payment is applied. | Foreign key to `borrowing_transactions.transaction_id`. Multiple payment rows may relate to one transaction when partial payments are supported. |
| `amount_paid` | Amount received in a payment record. | Sum payment records to calculate collections. Confirm currency and numeric precision. |
| `payment_channel` | Channel through which payment was recorded. | Supports payment-channel reporting. Do not label every record eCitizen unless the field values substantiate that claim. |

**Aggregation warning:** Aggregate payments by `transaction_id` before joining them to borrowing transactions for transaction-level or member-level fine analysis. A direct one-to-many join can repeat `fine_amount` and inflate accrued-fine totals.

## 5. Relationships and cardinality

| Parent | Child | Relationship | Join condition |
|---|---|---|---|
| `books` | `inventory_items` | One title can have multiple physical copies. | `books.book_id = inventory_items.book_id` |
| `members` | `borrowing_transactions` | One member can have multiple borrowing transactions. | `members.member_id = borrowing_transactions.member_id` |
| `inventory_items` | `borrowing_transactions` | One physical copy can appear in multiple transactions over time. | `inventory_items.copy_id = borrowing_transactions.copy_id` |
| `borrowing_transactions` | `fine_payments` | One transaction can have zero, one, or multiple payment records. | `borrowing_transactions.transaction_id = fine_payments.transaction_id` |

Confirm that these relationships are implemented as foreign-key constraints in PostgreSQL. Documented joins alone do not prove that constraints exist.

## 6. Reporting measures and definitions

These are proposed business definitions. Validate them against the implemented DAX and SQL before publishing final figures.

| Measure | Business definition | Validation required |
|---|---|---|
| Total Active Members | Distinct count of members considered active under an agreed business rule. | The README's example counts all distinct member IDs. That is not necessarily an active-member definition unless the model filters to active members. |
| Total Fines Accrued | Sum of fine amounts accrued on borrowing transactions in the selected reporting scope. | Prevent duplication when joining to multiple payment rows. Define treatment of reversed or adjusted fines if applicable. |
| Total Revenue Collected | Sum of valid payment amounts received in the selected reporting scope. | Reconcile payment records to a trusted payment source if one exists; distinguish recorded payments from verified settlements. |
| Unpaid Fines at Risk | Fine amount accrued less payments applied to those fines, under agreed accounting rules. | Aggregate payments per transaction first; define treatment of overpayments, reversals, write-offs, and negative balances. |
| Active Utilization Rate | Distinct physical copies currently borrowed divided by eligible inventory copies, multiplied by 100. | Define the eligible denominator. The README's example counts unreturned transaction rows, which may overcount copies. |
| Inventory Status Count | Count of physical copies by current status. | Count from `inventory_items`, not from a transaction-level joined view. |
| Borrowing Trend | Number of borrowing transactions grouped by issue month or another explicitly selected date. | Use a consistent date field and reporting calendar. |
| Outstanding Fines by Member | Accrued fines less payments allocated to that member's transactions. | Aggregate payments by transaction before member-level aggregation and separately handle invalid negative balances. |

## 7. Data quality and reconciliation checks

Run and record the results against the actual PostgreSQL database. Do not mark a check as passed until the query has been executed and its output reviewed.

1. **Schema verification:** Confirm actual tables, columns, data types, primary/foreign keys, nullability, defaults, and indexes.
2. **Primary-key uniqueness:** Confirm no duplicate IDs in each entity's documented primary key.
3. **Referential integrity:** Check for transactions with missing members or inventory copies, inventory copies with missing book records, and payments with missing borrowing transactions.
4. **Transaction uniqueness:** Check whether each `transaction_id` appears once in the circulation view. Multiple rows may indicate a one-to-many join issue rather than duplicate source transactions.
5. **Payment reconciliation:** Compare payment-record totals with trusted payment totals, if a trusted source exists.
6. **Fine reconciliation:** Verify fine totals before and after joining payment records to prevent fan-out inflation.
7. **Date validity:** Check issue dates against due and return dates; investigate impossible or inconsistent sequences.
8. **Inventory consistency:** Compare current inventory statuses with active borrowing records and investigate contradictions.
9. **Null and domain checks:** Review missing required values and values outside permitted status, category, or payment-channel lists.
10. **Privacy review:** Confirm that reports, screenshots, exports, and sample data do not reveal real personal contact details.

## 8. Privacy, security, and responsible use

- Keep the project synthetic; do not commit real patron records, payment exports, phone numbers, or credentials.
- Apply least-privilege access to source tables and analytical views.
- Prefer masked or aggregated values in dashboards and screenshots.
- Store database credentials outside source control, using environment variables or an approved secrets manager.
- Masking a phone number is a risk-reduction measure, not proof of full legal compliance. Compliance depends on the full processing context, lawful basis, purpose limitation, retention, access controls, data-subject rights, and other applicable obligations.
- Describe eCitizen as a simulated/modeled payment channel unless a live, authorized integration has actually been implemented and tested.

## 9. Items to confirm before sign-off

- [ ] Match all documented fields and relationships against the actual PostgreSQL DDL.
- [ ] Record physical data types, nullability, defaults, constraints, and indexes.
- [ ] Confirm whether `masked_phone` is stored, computed, or supplied by a transformation.
- [ ] Define “active member” and implement the corresponding filter if needed.
- [ ] Define the utilization numerator and denominator, and count unique physical copies.
- [ ] Aggregate `fine_payments` before joining to transaction-level fine data.
- [ ] Verify headline metrics against executed SQL and Power BI outputs.
- [ ] Replace unsupported “real-time,” “live integration,” or “full compliance” claims with precise descriptions of what has actually been implemented and validated.

---

**Document status:** Initial data dictionary based on fields and relationships described in the repository README. Update it after comparing it with the actual database schema and tested reporting logic.
