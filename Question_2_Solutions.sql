
/*
============================================================


QUESTION 3: LIBRARY RETURNS AND OVERDUE FINE

============================================================
*/


-- ==========================================================
-- QUESTION 3 (A): DATABASE AND SEED DATA [6 MARKS]
-- Create tables and insert three books and six loans.
-- ==========================================================

-- Create a separate schema for Question 3
CREATE SCHEMA IF NOT EXISTS q3;

SET search_path TO q3, public;


-- 1. BOOKS TABLE
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(150) NOT NULL
);


-- 2. LOANS TABLE
CREATE TABLE loans (
    loan_id SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL,
    borrower_name VARCHAR(100) NOT NULL,
    borrowed_on DATE NOT NULL,
    due_on DATE NOT NULL,
    returned_on DATE,
    fine_amount NUMERIC(10,2) NOT NULL DEFAULT 0
        CHECK (fine_amount >= 0),

    FOREIGN KEY (book_id)
    REFERENCES books(book_id),

    CHECK (due_on >= borrowed_on),

    CHECK (
        returned_on IS NULL
        OR returned_on >= borrowed_on
    )
);


-- 3. LOAN AUDIT TABLE
CREATE TABLE loan_audit (
    audit_id SERIAL PRIMARY KEY,
    loan_id INTEGER NOT NULL,
    old_returned_on DATE,
    new_returned_on DATE,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (loan_id)
    REFERENCES loans(loan_id)
);


-- 4. OVERDUE SUMMARY TABLE
CREATE TABLE overdue_summary (
    snapshot_date DATE PRIMARY KEY,
    overdue_count INTEGER NOT NULL,
    total_fine NUMERIC(12,2) NOT NULL
);


-- Insert three books
INSERT INTO books (title)
VALUES
('Database Management Systems'),
('Introduction to Programming'),
('Computer Networks');


-- Insert six loans
-- Loan 1: Open overdue loan
-- Loan 2: On-time loan (returned on due date)
-- Loan 3: Late return
-- Loans 4, 5 and 6: Not yet overdue

INSERT INTO loans (
    book_id,
    borrower_name,
    borrowed_on,
    due_on,
    returned_on,
    fine_amount
)
VALUES
(1, 'John Banda', CURRENT_DATE - 30,
 CURRENT_DATE - 10, NULL, 0),

(2, 'Mary Phiri', CURRENT_DATE - 15,
 CURRENT_DATE, NULL, 0),

(3, 'Peter Zulu', CURRENT_DATE - 20,
 CURRENT_DATE - 5, NULL, 0),

(1, 'Grace Tembo', CURRENT_DATE - 5,
 CURRENT_DATE + 5, NULL, 0),

(2, 'James Mwale', CURRENT_DATE - 2,
 CURRENT_DATE + 10, NULL, 0),

(3, 'Sarah Chanda', CURRENT_DATE - 1,
 CURRENT_DATE + 15, NULL, 0);



-- ==========================================================
-- QUESTION 3 (B): FUNCTION [6 MARKS]
-- Function: fn_loan_fine
-- Calculates K2 for every overdue day.
-- A returned loan stops accumulating fines.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_loan_fine(
    p_loan_id INTEGER,
    p_as_of DATE
)
RETURNS NUMERIC(10,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_due_on DATE;
    v_returned_on DATE;
    v_effective_date DATE;
    v_overdue_days INTEGER;
BEGIN

    -- Validate date
    IF p_as_of IS NULL THEN
        RAISE EXCEPTION 'Calculation date cannot be NULL';
    END IF;

    -- Retrieve loan information
    SELECT due_on, returned_on
    INTO v_due_on, v_returned_on
    FROM loans
    WHERE loan_id = p_loan_id;

    -- Reject unknown loan
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan ID % does not exist',
        p_loan_id;
    END IF;

    -- Use the earlier of the calculation date
    -- and the actual return date.
    IF v_returned_on IS NOT NULL THEN
        v_effective_date := LEAST(p_as_of, v_returned_on);
    ELSE
        v_effective_date := p_as_of;
    END IF;

    -- Calculate overdue days
    v_overdue_days :=
        GREATEST(v_effective_date - v_due_on, 0);

    -- Return fine at K2 per overdue day
    RETURN v_overdue_days * 2.00;

END;
$$;



-- ==========================================================
-- QUESTION 3 (C): PROCEDURE [8 MARKS]
-- Procedure: pr_return_loan
-- Records a book return and calculates the final fine.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_return_loan(
    p_loan_id INTEGER,
    p_returned_on DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_borrowed_on DATE;
    v_existing_return DATE;
    v_final_fine NUMERIC(10,2);
BEGIN

    -- Validate return date
    IF p_returned_on IS NULL THEN
        RAISE EXCEPTION 'Return date cannot be NULL';
    END IF;

    -- Retrieve loan information and lock its row
    SELECT borrowed_on, returned_on
    INTO v_borrowed_on, v_existing_return
    FROM loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    -- Reject unknown loan
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan ID % does not exist',
        p_loan_id;
    END IF;

    -- Reject an already returned loan
    IF v_existing_return IS NOT NULL THEN
        RAISE EXCEPTION 'This loan has already been returned';
    END IF;

    -- Return date cannot be before borrowed date
    IF p_returned_on < v_borrowed_on THEN
        RAISE EXCEPTION
        'Return date cannot be before borrowed date';
    END IF;

    -- Calculate final fine
    v_final_fine := fn_loan_fine(
        p_loan_id,
        p_returned_on
    );

    -- Update return date and final fine together
    UPDATE loans
    SET
        returned_on = p_returned_on,
        fine_amount = v_final_fine
    WHERE loan_id = p_loan_id;

END;
$$;



-- ==========================================================
-- QUESTION 3 (D): TRIGGER [8 MARKS]
-- Trigger: trg_loan_audit
-- Records changes to returned_on using OLD and NEW.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_loan_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    -- Check whether the return date actually changed
    IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN

        INSERT INTO loan_audit (
            loan_id,
            old_returned_on,
            new_returned_on,
            changed_at
        )
        VALUES (
            NEW.loan_id,
            OLD.returned_on,
            NEW.returned_on,
            CURRENT_TIMESTAMP
        );

    END IF;

    RETURN NEW;

END;
$$;


-- Create AFTER UPDATE trigger
CREATE TRIGGER trg_loan_audit
AFTER UPDATE ON loans
FOR EACH ROW
EXECUTE FUNCTION fn_loan_audit();



-- ==========================================================
-- QUESTION 3 (A): SEED DATA CONTINUED
-- Test the return procedure.
-- Return one book on time and another late.
-- ==========================================================

-- Return loan 2 on its due date (no fine)
CALL pr_return_loan(
    2,
    CURRENT_DATE
);

-- Return loan 3 two days before today.
-- Its due date was five days before today.
-- Therefore, the fine is K6.
CALL pr_return_loan(
    3,
    CURRENT_DATE - 2
);



-- ==========================================================
-- QUESTION 3 (E): VIEW [5 MARKS]
-- View: v_overdue_loans
-- Shows currently unreturned loans past their due dates.
-- Includes book title, borrower, due date and current fine.
-- ==========================================================

CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT
    l.loan_id,
    b.title,
    l.borrower_name,
    l.due_on,
    fn_loan_fine(l.loan_id, CURRENT_DATE) AS fine_amount
FROM loans l
JOIN books b
    ON l.book_id = b.book_id
WHERE l.returned_on IS NULL
AND l.due_on < CURRENT_DATE;


-- Display overdue loans
SELECT * FROM v_overdue_loans;



-- ==========================================================
-- QUESTION 3 (F): INDEX [5 MARKS]
-- Index: idx_loans_book_unreturned
-- Supports searching for unreturned loans by book.
-- ==========================================================

-- Create a partial index
CREATE INDEX idx_loans_book_unreturned
ON loans (book_id)
WHERE returned_on IS NULL;


-- Matching query
SELECT *
FROM loans
WHERE book_id = 1
AND returned_on IS NULL;


-- Display execution plan
EXPLAIN
SELECT *
FROM loans
WHERE book_id = 1
AND returned_on IS NULL;


-- Index justification:
-- The index contains only loans that have not been returned.
-- book_id supports searching for loans belonging to
-- a particular book.
-- This reduces the index size and supports the query.



-- ==========================================================
-- QUESTION 3 (G): SCHEDULED JOB [6 MARKS]
-- Procedure: pr_refresh_overdue
-- Counts loans still unreturned as of a specified date.
-- Calculates total fines and replaces existing summaries.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_overdue(
    p_as_of DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_overdue_count INTEGER;
    v_total_fine NUMERIC(12,2);
BEGIN

    -- Validate calculation date
    IF p_as_of IS NULL THEN
        RAISE EXCEPTION 'Snapshot date cannot be NULL';
    END IF;

    -- Count loans that were still unreturned
    -- as of the specified date.
    -- A loan returned after that date was still
    -- outstanding on the snapshot date.
    SELECT
        COUNT(*)::INTEGER,
        COALESCE(
            SUM(fn_loan_fine(loan_id, p_as_of)),
            0
        )
    INTO
        v_overdue_count,
        v_total_fine
    FROM loans
    WHERE returned_on IS NULL
       OR returned_on > p_as_of;

    -- Insert or replace the overdue summary
    INSERT INTO overdue_summary (
        snapshot_date,
        overdue_count,
        total_fine
    )
    VALUES (
        p_as_of,
        v_overdue_count,
        v_total_fine
    )
    ON CONFLICT (snapshot_date)
    DO UPDATE SET
        overdue_count = EXCLUDED.overdue_count,
        total_fine = EXCLUDED.total_fine;

END;
$$;


-- Manually test the procedure
CALL pr_refresh_overdue(CURRENT_DATE);


-- Display overdue summary
SELECT * FROM overdue_summary;



-- ==========================================================
-- SCHEDULE THE DAILY JOB USING PG_CRON
-- Run daily at 00:10 for CURRENT_DATE.
-- Requires pg_cron installation and configuration.
-- ==========================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule daily execution at 00:10
SELECT cron.schedule(
    'refresh_library_overdue',
    '10 0 * * *',
    'CALL q3.pr_refresh_overdue(CURRENT_DATE);'
);


-- Display scheduled jobs
SELECT * FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 3
-- ==========================================================

-- 1. Display all books
SELECT * FROM books;

-- 2. Display all loans
SELECT * FROM loans;

-- 3. Display loan audit records
SELECT * FROM loan_audit;

-- 4. Display overdue loans
SELECT * FROM v_overdue_loans;

-- 5. Display overdue summary
SELECT * FROM overdue_summary;

-- 6. Test fine calculation for loan 1
SELECT fn_loan_fine(1, CURRENT_DATE);

-- 7. Test fine calculation for returned loan 2
SELECT fn_loan_fine(2, CURRENT_DATE);

-- 8. Test fine calculation for returned loan 3
SELECT fn_loan_fine(3, CURRENT_DATE);

-- 9. Refresh overdue summary
CALL pr_refresh_overdue(CURRENT_DATE);

-- 10. Display updated summary
SELECT * FROM overdue_summary;


-- ==========================================================
-- END OF QUESTION 3
-- ==========================================================
