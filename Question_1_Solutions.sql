
/*
============================================================
QUESTION 1: PHARMACY STOCK AND DAILY SALES
============================================================
*/


-- ==========================================================
-- QUESTION 1 (A): DATABASE AND SEED DATA [6 MARKS]
-- Create the four required tables.
-- ==========================================================

-- Create a separate schema for Question 1
CREATE SCHEMA IF NOT EXISTS q1;

SET search_path TO q1, public;


-- 1. MEDICINES TABLE
CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    stock_qty INTEGER NOT NULL CHECK (stock_qty >= 0)
);


-- 2. SALES TABLE
CREATE TABLE sales (
    sale_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    sold_on DATE NOT NULL,

    FOREIGN KEY (medicine_id)
    REFERENCES medicines(medicine_id)
);


-- 3. STOCK AUDIT TABLE
CREATE TABLE stock_audit (
    audit_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL,
    old_qty INTEGER NOT NULL,
    new_qty INTEGER NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (medicine_id)
    REFERENCES medicines(medicine_id)
);


-- 4. DAILY SALES TABLE
CREATE TABLE daily_sales (
    sales_date DATE PRIMARY KEY,
    total_qty INTEGER NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL
);


-- Insert three medicines
INSERT INTO medicines (medicine_name, unit_price, stock_qty)
VALUES
('Paracetamol', 5.00, 100),
('Amoxicillin', 15.00, 80),
('Cough Syrup', 25.00, 50);



-- ==========================================================
-- QUESTION 1 (B): FUNCTION [6 MARKS]
-- Function: fn_sale_value
-- Returns current unit price multiplied by quantity.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_sale_value(
    p_medicine_id INTEGER,
    p_quantity INTEGER
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_price NUMERIC(10,2);
BEGIN

    -- Validate quantity
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be greater than zero';
    END IF;

    -- Retrieve medicine price
    SELECT unit_price
    INTO v_price
    FROM medicines
    WHERE medicine_id = p_medicine_id;

    -- Reject unknown medicine
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine ID % does not exist',
        p_medicine_id;
    END IF;

    -- Calculate and return sale value
    RETURN v_price * p_quantity;

END;
$$;



-- ==========================================================
-- QUESTION 1 (C): PROCEDURE [8 MARKS]
-- Procedure: pr_record_sale
-- Checks stock, records sale and deducts stock.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_record_sale(
    p_medicine_id INTEGER,
    p_quantity INTEGER,
    p_sold_on DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_price NUMERIC(10,2);
    v_stock INTEGER;
BEGIN

    -- Validate quantity
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity';
    END IF;

    -- Validate sale date
    IF p_sold_on IS NULL THEN
        RAISE EXCEPTION 'Sale date cannot be NULL';
    END IF;

    -- Retrieve medicine and lock its row
    SELECT unit_price, stock_qty
    INTO v_price, v_stock
    FROM medicines
    WHERE medicine_id = p_medicine_id
    FOR UPDATE;

    -- Check if medicine exists
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine not found';
    END IF;

    -- Check available stock
    IF v_stock < p_quantity THEN
        RAISE EXCEPTION
        'Insufficient stock. Available: %, Requested: %',
        v_stock, p_quantity;
    END IF;

    -- Record the sale using current medicine price
    INSERT INTO sales (
        medicine_id,
        quantity,
        unit_price,
        sold_on
    )
    VALUES (
        p_medicine_id,
        p_quantity,
        v_price,
        p_sold_on
    );

    -- Deduct stock exactly once
    UPDATE medicines
    SET stock_qty = stock_qty - p_quantity
    WHERE medicine_id = p_medicine_id;

END;
$$;



-- ==========================================================
-- QUESTION 1 (D): TRIGGER [8 MARKS]
-- Trigger: trg_stock_audit
-- Records stock changes using OLD and NEW values.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_stock_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    -- Check whether stock quantity actually changed
    IF OLD.stock_qty IS DISTINCT FROM NEW.stock_qty THEN

        INSERT INTO stock_audit (
            medicine_id,
            old_qty,
            new_qty,
            changed_at
        )
        VALUES (
            NEW.medicine_id,
            OLD.stock_qty,
            NEW.stock_qty,
            CURRENT_TIMESTAMP
        );

    END IF;

    RETURN NEW;

END;
$$;


-- Create AFTER UPDATE trigger
CREATE TRIGGER trg_stock_audit
AFTER UPDATE ON medicines
FOR EACH ROW
EXECUTE FUNCTION fn_stock_audit();



-- ==========================================================
-- QUESTION 1 (A): SEED DATA CONTINUED
-- Load at least six valid sales through the procedure.
-- ==========================================================

CALL pr_record_sale(1, 5, CURRENT_DATE);
CALL pr_record_sale(2, 3, CURRENT_DATE);
CALL pr_record_sale(3, 2, CURRENT_DATE);
CALL pr_record_sale(1, 4, CURRENT_DATE);
CALL pr_record_sale(2, 6, CURRENT_DATE);
CALL pr_record_sale(3, 1, CURRENT_DATE);



-- ==========================================================
-- QUESTION 1 (E): VIEW [5 MARKS]
-- View: v_low_stock
-- Shows medicines with stock below 10.
-- ==========================================================

CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    medicine_id,
    medicine_name,
    unit_price,
    stock_qty
FROM medicines
WHERE stock_qty < 10;


-- Display low-stock medicines
SELECT * FROM v_low_stock;



-- ==========================================================
-- QUESTION 1 (F): INDEX [5 MARKS]
-- Index: idx_sales_medicine_date
-- Supports medicine and date-range searches.
-- ==========================================================

CREATE INDEX idx_sales_medicine_date
ON sales (medicine_id, sold_on);


-- Matching query
SELECT *
FROM sales
WHERE medicine_id = 1
AND sold_on BETWEEN DATE '2026-11-01'
                AND DATE '2026-11-30';


-- Display execution plan
EXPLAIN
SELECT *
FROM sales
WHERE medicine_id = 1
AND sold_on BETWEEN DATE '2026-11-01'
                AND DATE '2026-11-30';

-- Justification:
-- The composite index (medicine_id, sold_on) supports searches
-- for a specific medicine within a date range. PostgreSQL can
-- first locate rows by medicine_id and then efficiently filter
-- by sold_on, reducing table scans and improving query performance.



-- ==========================================================
-- QUESTION 1 (G): SCHEDULED JOB [6 MARKS]
-- Procedure: pr_refresh_sales
-- Calculates daily sales quantity and revenue.
-- Replaces existing summary when rerun.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_sales(
    p_day DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_qty INTEGER;
    v_total_amount NUMERIC(12,2);
BEGIN

    -- Validate date
    IF p_day IS NULL THEN
        RAISE EXCEPTION 'Sales date cannot be NULL';
    END IF;

    -- Calculate daily sales totals
    SELECT
        COALESCE(SUM(quantity), 0),
        COALESCE(SUM(quantity * unit_price), 0)
    INTO
        v_total_qty,
        v_total_amount
    FROM sales
    WHERE sold_on = p_day;

    -- Insert or update daily sales summary
    INSERT INTO daily_sales (
        sales_date,
        total_qty,
        total_amount
    )
    VALUES (
        p_day,
        v_total_qty,
        v_total_amount
    )
    ON CONFLICT (sales_date)
    DO UPDATE SET
        total_qty = EXCLUDED.total_qty,
        total_amount = EXCLUDED.total_amount;

END;
$$;


-- Manually test the procedure
CALL pr_refresh_sales(CURRENT_DATE);


-- Enable pg_cron extension
-- Requires pg_cron to be installed and configured
-- on the PostgreSQL server.

CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule daily execution at 00:15
-- The procedure processes the previous day's sales.

SELECT cron.schedule(
    'refresh_pharmacy_sales',
    '15 0 * * *',
    'CALL q1.pr_refresh_sales(CURRENT_DATE - 1);'
);


-- View scheduled jobs
SELECT * FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 1
-- Display all records and test the completed objects.
-- ==========================================================

-- Display medicines
SELECT * FROM medicines;

-- Display sales
SELECT * FROM sales;

-- Display stock audit history
SELECT * FROM stock_audit;

-- Display low-stock medicines
SELECT * FROM v_low_stock;

-- Display daily sales summary
SELECT * FROM daily_sales;

-- Test sale value function
SELECT fn_sale_value(1, 5);

-- Test daily sales procedure
CALL pr_refresh_sales(CURRENT_DATE);

-- Display updated daily sales
SELECT * FROM daily_sales;


-- ==========================================================
-- END OF QUESTION 1
-- ==========================================================
