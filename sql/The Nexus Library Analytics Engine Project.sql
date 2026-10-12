data@2016

-- THE NEXUS LIBRARY ANALYTICS ENGINE
-- SECTION 1: CREATE DATABASE
CREATE DATABASE nexus_library_db;

SELECT current_database();

--================================================================================================

-- SECTION 2: CREATE TABLES
-- 1. Create Members Table (with Data Privacy Controls)
CREATE TABLE members (
    member_id SERIAL PRIMARY KEY,
    member_code VARCHAR(20) UNIQUE NOT NULL,      -- e.g., 'KNLS-2026-001'
    hashed_national_id VARCHAR(64) NOT NULL,      -- Masked ID (DPA Compliance)
    gender VARCHAR(10),
    category VARCHAR(20) CHECK (category IN ('Adult', 'Student', 'Child', 'Researcher')),
    masked_phone VARCHAR(15),                     -- e.g., '2547XXXXX123'
    consent_signed BOOLEAN DEFAULT TRUE,          -- Explicit Consent Flag
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Create Books Table
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    isbn VARCHAR(20) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    author VARCHAR(150) NOT NULL,
    category_section VARCHAR(50) NOT NULL,        -- e.g., 'American Corner', 'Children', 'Bibliography'
    publication_year INT
);

-- 3. Create Book Copies (Inventory)
CREATE TABLE inventory_items (
    copy_id SERIAL PRIMARY KEY,
    book_id INT REFERENCES books(book_id) ON DELETE CASCADE,
    barcode VARCHAR(50) UNIQUE NOT NULL,
    status VARCHAR(20) DEFAULT 'Available' CHECK (status IN ('Available', 'Borrowed', 'Under Maintenance', 'Lost'))
);

-- 4. Create Borrowing Transactions Table
CREATE TABLE borrowing_transactions (
    transaction_id SERIAL PRIMARY KEY,
    copy_id INT REFERENCES inventory_items(copy_id),
    member_id INT REFERENCES members(member_id),
    issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE NOT NULL,
    return_date DATE,                            -- NULL if book is still with borrower
    fine_amount DECIMAL(10, 2) DEFAULT 0.00
);

-- 5. Create Fine Payments Table
CREATE TABLE fine_payments (
    payment_id SERIAL PRIMARY KEY,
    transaction_id INT REFERENCES borrowing_transactions(transaction_id),
    amount_paid DECIMAL(10, 2) NOT NULL,
    payment_reference VARCHAR(50) UNIQUE NOT NULL, -- eCitizen receipt number
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

--=============================================================================================

-- SECTION 3: INSERT DATA INTO TABLE

-- 1. Clear existing sample data (if any)
TRUNCATE fine_payments, borrowing_transactions, inventory_items, books, members RESTART IDENTITY CASCADE;

-- 2. Generate 500 Realistic Members (DPA Compliant)
INSERT INTO members (member_code, hashed_national_id, gender, category, masked_phone, consent_signed, created_at)
SELECT 
    'NEX-2026-' || LPAD(s.id::text, 4, '0'),
    md5(s.id::text || 'secret_salt_2026'),
    (ARRAY['Male', 'Female'])[FLOOR(RANDOM() * 2 + 1)],
    (ARRAY['Adult', 'Student', 'Child', 'Researcher'])[FLOOR(RANDOM() * 4 + 1)],
    '2547' || LPAD(FLOOR(RANDOM() * 89999999 + 10000000)::text, 8, '0'),
    TRUE,
    CURRENT_DATE - (FLOOR(RANDOM() * 365) || ' days')::INTERVAL
FROM generate_series(1, 500) AS s(id);

-- 3. Populate 200 Broad Book Titles across diverse genres
INSERT INTO books (isbn, title, author, category_section, publication_year)
SELECT 
    '978-' || LPAD(FLOOR(RANDOM() * 899999999 + 100000000)::text, 9, '0') || '-' || FLOOR(RANDOM() * 9 + 1)::text,
    'Book Title Vol. ' || s.id,
    'Author ' || (ARRAY['Ngũgĩ wa Thiong''o', 'Yvonne Owuor', 'Harper Lee', 'James Clear', 'Chinua Achebe', 'Binyavanga Wainaina', 'Ali Mazrui'])[FLOOR(RANDOM() * 7 + 1)],
    (ARRAY['Kenyan Literature', 'General Fiction', 'Digital Data Centre', 'Self-Help & Business', 'American Corner', 'Children Section', 'Bibliography & Archives'])[FLOOR(RANDOM() * 7 + 1)],
    FLOOR(RANDOM() * (2025 - 1960 + 1) + 1960)::INT
FROM generate_series(1, 200) AS s(id);

-- 4. Create ~800 Physical Copies (Inventory)
INSERT INTO inventory_items (book_id, barcode, status)
SELECT 
    FLOOR(RANDOM() * 200 + 1)::INT,
    'BC-NEX-' || LPAD(s.id::text, 5, '0'),
    (ARRAY['Available', 'Borrowed', 'Under Maintenance', 'Lost'])[FLOOR(RANDOM() * 4 + 1)]
FROM generate_series(1, 800) AS s(id);

-- 5. Generate 2,500 Borrowing Transactions over the past year
INSERT INTO borrowing_transactions (copy_id, member_id, issue_date, due_date, return_date, fine_amount)
SELECT 
    FLOOR(RANDOM() * 800 + 1)::INT,
    FLOOR(RANDOM() * 500 + 1)::INT,
    issue_dt,
    issue_dt + INTERVAL '14 days',
    CASE 
        WHEN RANDOM() < 0.20 THEN NULL -- 20% currently unreturned
        ELSE issue_dt + (FLOOR(RANDOM() * 25) || ' days')::INTERVAL -- Returned between 0 to 25 days
    END,
    0.00
FROM (
    SELECT CURRENT_DATE - (FLOOR(RANDOM() * 300) || ' days')::INTERVAL AS issue_dt
    FROM generate_series(1, 2500)
) sub;

-- Update Fine Amounts for overdue/late returns (50 KSh per overdue day)
UPDATE borrowing_transactions
SET fine_amount = CASE 
    WHEN return_date IS NOT NULL AND return_date > due_date THEN (return_date - due_date) * 50.00
    WHEN return_date IS NULL AND CURRENT_DATE > due_date THEN (CURRENT_DATE - due_date) * 50.00
    ELSE 0.00
END;

-- 6. Generate Fine Payments for settled fines
INSERT INTO fine_payments (transaction_id, amount_paid, payment_reference, payment_date)
SELECT 
    transaction_id,
    fine_amount,
    'ECIT-2026-' || LPAD(transaction_id::text, 6, '0'),
    COALESCE(return_date, CURRENT_DATE)
FROM borrowing_transactions
WHERE fine_amount > 0 AND RANDOM() < 0.75; -- 75% of fines paid via eCitizen


--checking row count
SELECT 'members' AS table_name, COUNT(*) FROM members
UNION ALL
SELECT 'books', COUNT(*) FROM books
UNION ALL
SELECT 'inventory_items', COUNT(*) FROM inventory_items
UNION ALL
SELECT 'borrowing_transactions', COUNT(*) FROM borrowing_transactions
UNION ALL
SELECT 'fine_payments', COUNT(*) FROM fine_payments;

--========================================================================================
--SECTION 4

-- Data Cleaning & DPA Compliance Refactoring

SELECT * FROM public.members;

-- 1. Enforce DPA Masking on Phone Numbers (Converts '254712345678' -> '2547XXXXX678')
UPDATE members
SET masked_phone = SUBSTRING(masked_phone FROM 1 FOR 4) || 'XXXXX' || RIGHT(masked_phone, 3)
WHERE masked_phone NOT LIKE '%XXXXX%';

-- 2. Ensure National IDs are hashed
UPDATE members
SET hashed_national_id = MD5(hashed_national_id || 'nexus_salt_2026')
WHERE LENGTH(hashed_national_id) < 32;

-- 3. Impute NULL fine amounts to 0.00
SELECT * FROM public.borrowing_transactions;

UPDATE borrowing_transactions
SET fine_amount = 0.00
WHERE fine_amount IS NULL;


SELECT * FROM public.books;
SELECT * FROM public.fine_payments;
SELECT * FROM public.inventory_items;

--============================================================================================

-- SECTION 5: Exploratory Data Analysis
-- Total Entity Record Counts
SELECT 'members' AS entity_name, COUNT(*) AS record_count FROM members
UNION ALL
SELECT 'books', COUNT(*) FROM books
UNION ALL
SELECT 'inventory_items', COUNT(*) FROM inventory_items
UNION ALL
SELECT 'borrowing_transactions', COUNT(*) FROM borrowing_transactions
UNION ALL
SELECT 'fine_payments', COUNT(*) FROM fine_payments;


--Date Bounds and Operational Timeline
SELECT 
    MIN(issue_date) AS earliest_borrow_date,
    MAX(issue_date) AS latest_borrow_date,
    MAX(return_date) AS latest_return_date,
    (MAX(issue_date) - MIN(issue_date)) AS operational_span_days
FROM borrowing_transactions;

--Demographic Distribution
SELECT 
    category,
    gender,
    COUNT(member_id) AS total_patrons,
    ROUND((COUNT(member_id)::DECIMAL / (SELECT COUNT(*) FROM members)) * 100, 2) AS category_percentage
FROM members
GROUP BY category, gender
ORDER BY category, total_patrons DESC;

--Inventory Physical Condition Breakdown
SELECT 
    status,
    COUNT(copy_id) AS total_copies,
    ROUND((COUNT(copy_id)::DECIMAL / (SELECT COUNT(*) FROM inventory_items)) * 100, 2) AS status_percentage
FROM inventory_items
GROUP BY status
ORDER BY total_copies DESC;

--Missingnes and Null Value Audit
SELECT 
    COUNT(*) FILTER (WHERE issue_date IS NULL) AS null_issue_dates,
    COUNT(*) FILTER (WHERE due_date IS NULL) AS null_due_dates,
    COUNT(*) FILTER (WHERE member_id IS NULL) AS unassigned_borrowers,
    COUNT(*) FILTER (WHERE copy_id IS NULL) AS unassigned_inventory_items
FROM borrowing_transactions;

--=============================================================================================================
--SECTION 6: Business Analysis
--Question 1: Member Distribution by Patron Category
SELECT
	category,
	COUNT(member_id) AS total_members
FROM members
GROUP BY category
ORDER BY total_members DESC;

--Question 2: Physical Inventory Status Breakdown
SELECT 
	status AS inventory_status,
	COUNT(copy_id) AS total_copies
FROM inventory_items
GROUP BY status
ORDER BY total_copies DESC;

--Question 3: Breadth of Titles Across Library Sections
SELECT 
    category_section,
    COUNT(book_id) AS total_distinct_titles,
    MIN(publication_year) AS oldest_publication,
    MAX(publication_year) AS newest_publication
FROM books
GROUP BY category_section
ORDER BY total_distinct_titles DESC;

--Question 4: Recent Patron Acquisition Audit (Last 90 Days)
SELECT 
    member_code,
    category,
    created_at::DATE AS registration_date,
    CURRENT_DATE - created_at::DATE AS days_since_registration
FROM members
WHERE created_at >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY created_at DESC;

--Question 5: Active Overdue Borrowings Audit
--Business Intent: Identify unreturned books past their due date to calculate active risk exposure.

SELECT 
    t.transaction_id,
    m.member_code,
    b.title,
    i.barcode,
    t.issue_date,
    t.due_date,
    (CURRENT_DATE - t.due_date) AS days_overdue
FROM borrowing_transactions t
JOIN members m ON t.member_id = m.member_id
JOIN inventory_items i ON t.copy_id = i.copy_id
JOIN books b ON i.book_id = b.book_id
WHERE t.return_date IS NULL 
  AND t.due_date < CURRENT_DATE
ORDER BY days_overdue DESC;


--Question 6: Top 10 eCitizen Fine Collections
--Business Intent: Audit the largest single fine settlements processed via external payment integration (eCitizen).
SELECT 
    p.payment_id,
    p.payment_reference,
    p.amount_paid,
    p.payment_date::DATE AS settled_date,
    m.member_code,
    b.title
FROM fine_payments p
JOIN borrowing_transactions t ON p.transaction_id = t.transaction_id
JOIN members m ON t.member_id = m.member_id
JOIN inventory_items i ON t.copy_id = i.copy_id
JOIN books b ON i.book_id = b.book_id
ORDER BY p.amount_paid DESC
LIMIT 10;


-- Question 7A: Total Historical Demand (All-Time Popularity)
/*
Business Question: Looking back at all history, which book 
categories have been borrowed the most overall?
*/
SELECT 
    b.category_section,
    COUNT(t.transaction_id) AS total_historical_borrows
FROM books b
JOIN inventory_items i ON b.book_id = i.book_id
JOIN borrowing_transactions t ON i.copy_id = t.copy_id
GROUP BY b.category_section
ORDER BY total_historical_borrows DESC;

-- Question 7B: Current Active Circulation (Filtered by Inventory Status & Null Returns)
/*
Business Question: Right this moment, which book categories have 
the highest number of books currently checked out (unreturned)?
*/
SELECT 
    b.category_section,
    COUNT(t.transaction_id) AS active_books_currently_out
FROM books b
JOIN inventory_items i ON b.book_id = i.book_id
JOIN borrowing_transactions t ON i.copy_id = t.copy_id
WHERE t.return_date IS NULL 
  AND i.status = 'Borrowed' -- filter for return for data integrity
GROUP BY b.category_section
ORDER BY active_books_currently_out DESC;


-- Question 8: Fine Accuired vs. Fine Paid by Member Category
/*
Business Question: How much fine money was charged versus how 
much was actually collected for each member type?
*/
SELECT 
    m.category,
    SUM(t.fine_amount) AS total_fines_charged,
    COALESCE(SUM(p.amount_paid), 0.00) AS total_fines_paid,
    SUM(t.fine_amount) - COALESCE(SUM(p.amount_paid), 0.00) AS unpaid_fines
FROM members m
JOIN borrowing_transactions t ON m.member_id = t.member_id
LEFT JOIN fine_payments p ON t.transaction_id = p.transaction_id
GROUP BY m.category
ORDER BY unpaid_fines DESC;

-- Question 9: High-Risk Default Members (Unpaid Fines over 500 KSh)
-- Business Question: Who are the members with unreturned books and unpaid fines greater than 500 KSh?
SELECT 
    m.member_code,
    m.category,
    m.masked_phone,
    SUM(t.fine_amount) AS total_unpaid_fine
FROM members m
JOIN borrowing_transactions t ON m.member_id = t.member_id
WHERE t.return_date IS NULL 
  AND t.due_date < CURRENT_DATE
GROUP BY m.member_code, m.category, m.masked_phone
HAVING SUM(t.fine_amount) > 500.00
ORDER BY total_unpaid_fine DESC;


-- Question 10: Book Utilization Rate
-- Business Question: What percentage of copies for each book title are currently out on loan?

SELECT 
    b.title,
    COUNT(i.copy_id) AS total_copies,
    COUNT(CASE WHEN i.status = 'Borrowed' THEN 1 END) AS copies_borrowed,
    ROUND(
        (COUNT(CASE WHEN i.status = 'Borrowed' THEN 1 END)::DECIMAL / COUNT(i.copy_id)) * 100, 2
    ) AS percentage_borrowed
FROM books b
JOIN inventory_items i ON b.book_id = i.book_id
GROUP BY b.title
ORDER BY percentage_borrowed DESC;

-- Question 11: Average Loan Duration
-- Business Question: On average, how many days do members keep books before returning them?
SELECT 
    m.category,
    ROUND(AVG(t.return_date - t.issue_date), 1) AS avg_days_kept
FROM borrowing_transactions t
JOIN members m ON t.member_id = m.member_id
WHERE t.return_date IS NOT NULL
GROUP BY m.category
ORDER BY avg_days_kept DESC;

-- Question 12: Monthly Revenue Collection via eCitizen
-- Business Question: How much fine money did the library collect each month?
SELECT 
    TO_CHAR(payment_date, 'YYYY-MM') AS payment_month,
    COUNT(payment_id) AS total_payments,
    SUM(amount_paid) AS total_revenue_collected
FROM fine_payments
GROUP BY TO_CHAR(payment_date, 'YYYY-MM')
ORDER BY payment_month DESC;


-- Question 13: Top 3 Borrowers per Category (CTE & Window Function)
-- Business Question: Who are the top 3 most active library members inside each patron category?
WITH RankedBorrowers AS (
    SELECT 
        m.category,
        m.member_code,
        COUNT(t.transaction_id) AS total_books_borrowed,
        DENSE_RANK() OVER (
            PARTITION BY m.category 
            ORDER BY COUNT(t.transaction_id) DESC
        ) AS borrower_rank
    FROM members m
    JOIN borrowing_transactions t ON m.member_id = t.member_id
    GROUP BY m.category, m.member_code
)
SELECT 
    category,
    member_code,
    total_books_borrowed,
    borrower_rank
FROM RankedBorrowers
WHERE borrower_rank <= 3
ORDER BY category, borrower_rank;


-- Question 14: Cumulative Running Total of Fines (Running Total)
-- Business Question: How does our total fine revenue accumulate day by day across the year?
SELECT 
    payment_date::DATE AS payment_day,
    amount_paid AS daily_amount,
    SUM(amount_paid) OVER (
        ORDER BY payment_date::DATE 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total_revenue
FROM fine_payments
ORDER BY payment_day;


-- Question 15: Inventory Turnover & Replenishment Warning
/*
Business Question: Which book titles have high demand (borrowed 5+ times) 
compared to their physical stock count, flagging them for budget purchasing?
*/
SELECT 
    b.title,
    b.category_section,
    COUNT(DISTINCT i.copy_id) AS physical_stock_copies,
    COUNT(t.transaction_id) AS total_times_borrowed
FROM books b
JOIN inventory_items i ON b.book_id = i.book_id
LEFT JOIN borrowing_transactions t ON i.copy_id = t.copy_id
GROUP BY b.book_id, b.title, b.category_section
HAVING COUNT(t.transaction_id) >= 5
ORDER BY total_times_borrowed DESC;


-- Question 16: Patron Inactivity & Retention Risk
/*
Business Question: Which members registered more than 90 days ago but have never borrowed a single book? 
(Helps the library target re-engagement campaigns).
*/
SELECT 
    m.member_code,
    m.category,
    m.created_at::DATE AS registration_date
FROM members m
LEFT JOIN borrowing_transactions t ON m.member_id = t.member_id
WHERE t.transaction_id IS NULL
  AND m.created_at < CURRENT_DATE - INTERVAL '90 days'
ORDER BY m.created_at ASC;


-- Question 17: Month-over-Month Borrowing Volume Trend
-- Business Question: How do borrowing counts change from one month to the next using the LAG() window function?
WITH MonthlyBorrows AS (
    SELECT 
        TO_CHAR(issue_date, 'YYYY-MM') AS borrow_month,
        COUNT(transaction_id) AS current_month_borrows
    FROM borrowing_transactions
    GROUP BY TO_CHAR(issue_date, 'YYYY-MM')
)
SELECT 
    borrow_month,
    current_month_borrows,
    LAG(current_month_borrows, 1) OVER (ORDER BY borrow_month) AS previous_month_borrows,
    current_month_borrows - LAG(current_month_borrows, 1) OVER (ORDER BY borrow_month) AS monthly_difference
FROM MonthlyBorrows
ORDER BY borrow_month;


-- Question 18: DPA-Compliant Secure Analytical View
/*
Business Question: Create a secure database view for everyday reporting that hides 
sensitive member info while displaying operational metrics.
*/
CREATE OR REPLACE VIEW secure_borrowing_audit_view AS
SELECT 
    t.transaction_id,
    m.category,
    m.masked_phone, -- Already masked via DPA rules
    b.title,
    t.issue_date,
    t.due_date,
    t.return_date,
    t.fine_amount
FROM borrowing_transactions t
JOIN members m ON t.member_id = m.member_id
JOIN inventory_items i ON t.copy_id = i.copy_id
JOIN books b ON i.book_id = b.book_id;


SELECT * FROM secure_borrowing_audit_view;




