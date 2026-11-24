
/*
============================================================
QUESTION 9: FARMER COOPERATIVE MAIZE DELIVERIES
============================================================
*/


-- ==========================================================
-- QUESTION 9 (A): DATABASE AND SEED DATA [6 MARKS]
--
-- Create three tables:
-- 1. farmers
-- 2. deliveries
-- 3. daily_purchases
--
-- Prepare three farmers and six deliveries.
-- Delivery records will be loaded after installing
-- the pricing trigger.
-- ==========================================================

-- Create a separate schema for Question 9
CREATE SCHEMA IF NOT EXISTS q9;

SET search_path TO q9, public;


-- 1. FARMERS TABLE
CREATE TABLE farmers (
    farmer_id SERIAL PRIMARY KEY,

    farmer_number VARCHAR(30) UNIQUE NOT NULL,

    full_name VARCHAR(100) NOT NULL
);


-- 2. DELIVERIES TABLE
CREATE TABLE deliveries (
    delivery_id SERIAL PRIMARY KEY,

    farmer_id INTEGER NOT NULL,

    grade VARCHAR(1) NOT NULL,

    weight_kg NUMERIC(12,2) NOT NULL,

    unit_rate NUMERIC(10,2) NOT NULL DEFAULT 0,

    total_value NUMERIC(14,2) NOT NULL DEFAULT 0,

    delivered_on DATE NOT NULL,

    is_paid BOOLEAN NOT NULL DEFAULT FALSE,

    FOREIGN KEY (farmer_id)
    REFERENCES farmers(farmer_id),

    CHECK (weight_kg > 0),

    CHECK (unit_rate >= 0),

    CHECK (total_value >= 0)
);


-- 3. DAILY_PURCHASES TABLE
CREATE TABLE daily_purchases (
    purchase_date DATE PRIMARY KEY,

    total_weight NUMERIC(14,2) NOT NULL DEFAULT 0,

    total_value NUMERIC(16,2) NOT NULL DEFAULT 0,

    CHECK (total_weight >= 0),

    CHECK (total_value >= 0)
);


-- Insert three farmers
INSERT INTO farmers (
    farmer_number,
    full_name
)
VALUES
('F001', 'John Banda'),

('F002', 'Mary Phiri'),

('F003', 'Peter Zulu');



-- ==========================================================
-- QUESTION 9 (B): FUNCTION [6 MARKS]
--
-- Function: fn_maize_rate(p_grade)
--
-- Returns the appropriate price per kilogram.
--
-- Grade A = K5
-- Grade B = K4
-- Grade C = K3
--
-- Rejects NULL or unsupported grades.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_maize_rate(
    p_grade VARCHAR
)
RETURNS NUMERIC(10,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rate NUMERIC(10,2);
BEGIN

    -- Reject NULL grade
    IF p_grade IS NULL THEN

        RAISE EXCEPTION
        'Maize grade cannot be NULL';

    END IF;

    -- Determine the rate based on grade
    CASE UPPER(TRIM(p_grade))

        WHEN 'A' THEN

            v_rate := 5.00;

        WHEN 'B' THEN

            v_rate := 4.00;

        WHEN 'C' THEN

            v_rate := 3.00;

        ELSE

            RAISE EXCEPTION
            'Invalid maize grade: %. Only A, B and C are allowed',
            p_grade;

    END CASE;

    -- Return the calculated rate
    RETURN v_rate;

END;
$$;



-- ==========================================================
-- QUESTION 9 (C): PROCEDURE [8 MARKS]
--
-- Procedure: pr_receive_delivery
--
-- Parameters:
-- p_farmer_id
-- p_grade
-- p_weight
-- p_date
--
-- Validates the farmer and delivery inputs.
-- Inserts the basic delivery fields.
--
-- is_paid is initially FALSE.
--
-- The BEFORE INSERT trigger supplies unit_rate
-- and total_value automatically.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_receive_delivery(
    p_farmer_id INTEGER,
    p_grade VARCHAR,
    p_weight NUMERIC,
    p_date DATE
)
LANGUAGE plpgsql
AS $$
BEGIN

    -- Validate farmer ID
    IF p_farmer_id IS NULL THEN

        RAISE EXCEPTION
        'Farmer ID cannot be NULL';

    END IF;

    -- Check whether farmer exists
    IF NOT EXISTS (
        SELECT 1
        FROM farmers
        WHERE farmer_id = p_farmer_id
    ) THEN

        RAISE EXCEPTION
        'Farmer ID % does not exist',
        p_farmer_id;

    END IF;


    -- Validate maize grade
    -- The function checks whether the grade is valid.
    PERFORM fn_maize_rate(p_grade);


    -- Validate weight
    IF p_weight IS NULL OR p_weight <= 0 THEN

        RAISE EXCEPTION
        'Delivery weight must be greater than zero';

    END IF;


    -- Validate delivery date
    IF p_date IS NULL THEN

        RAISE EXCEPTION
        'Delivery date cannot be NULL';

    END IF;


    -- Insert delivery record.
    -- unit_rate and total_value are supplied
    -- automatically by the BEFORE INSERT trigger.

    INSERT INTO deliveries (
        farmer_id,
        grade,
        weight_kg,
        delivered_on,
        is_paid
    )
    VALUES (
        p_farmer_id,
        UPPER(TRIM(p_grade)),
        p_weight,
        p_date,
        FALSE
    );

END;
$$;



-- ==========================================================
-- QUESTION 9 (D): TRIGGER [8 MARKS]
--
-- Trigger: trg_calculate_delivery_value
--
-- BEFORE INSERT OR UPDATE trigger on deliveries.
--
-- Responsibilities:
-- 1. Reject non-positive weight.
-- 2. Call fn_maize_rate().
-- 3. Set NEW.unit_rate.
-- 4. Set NEW.total_value.
--
-- Direct SQL inserts and updates must follow
-- the same pricing rules.
-- ==========================================================


-- Create trigger function
CREATE OR REPLACE FUNCTION fn_calculate_delivery_value()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_rate NUMERIC(10,2);
BEGIN

    -- Validate delivery weight
    IF NEW.weight_kg IS NULL
       OR NEW.weight_kg <= 0 THEN

        RAISE EXCEPTION
        'Delivery weight must be greater than zero';

    END IF;


    -- Validate grade
    IF NEW.grade IS NULL THEN

        RAISE EXCEPTION
        'Maize grade cannot be NULL';

    END IF;


    -- Standardize grade to uppercase
    NEW.grade := UPPER(TRIM(NEW.grade));


    -- Retrieve the correct rate using the function
    v_rate := fn_maize_rate(NEW.grade);


    -- Automatically set unit rate
    NEW.unit_rate := v_rate;


    -- Calculate total delivery value
    NEW.total_value :=
        NEW.weight_kg * v_rate;


    -- Return updated delivery record
    RETURN NEW;

END;
$$;


-- Create BEFORE INSERT OR UPDATE trigger
CREATE TRIGGER trg_calculate_delivery_value

BEFORE INSERT OR UPDATE ON deliveries

FOR EACH ROW

EXECUTE FUNCTION fn_calculate_delivery_value();



-- ==========================================================
-- QUESTION 9 (A): SEED DATA CONTINUED
--
-- Insert six deliveries using the procedure.
--
-- Covers:
-- Grade A, Grade B and Grade C.
-- Both paid and unpaid delivery states.
--
-- All deliveries are initially unpaid because
-- the procedure sets is_paid to FALSE.
-- ==========================================================


-- FARMER 1: JOHN BANDA

-- Delivery 1:
-- Grade A
-- Weight: 100 kg
-- Rate: K5
-- Expected value: K500
CALL pr_receive_delivery(
    1,
    'A',
    100,
    DATE '2026-10-01'
);


-- Delivery 2:
-- Grade B
-- Weight: 50 kg
-- Rate: K4
-- Expected value: K200
CALL pr_receive_delivery(
    1,
    'B',
    50,
    DATE '2026-10-05'
);


-- FARMER 2: MARY PHIRI

-- Delivery 3:
-- Grade B
-- Weight: 80 kg
-- Rate: K4
-- Expected value: K320
CALL pr_receive_delivery(
    2,
    'B',
    80,
    DATE '2026-10-01'
);


-- Delivery 4:
-- Grade C
-- Weight: 40 kg
-- Rate: K3
-- Expected value: K120
CALL pr_receive_delivery(
    2,
    'C',
    40,
    DATE '2026-10-06'
);


-- FARMER 3: PETER ZULU

-- Delivery 5:
-- Grade C
-- Weight: 120 kg
-- Rate: K3
-- Expected value: K360
CALL pr_receive_delivery(
    3,
    'C',
    120,
    DATE '2026-10-02'
);


-- Delivery 6:
-- Grade A
-- Weight: 60 kg
-- Rate: K5
-- Expected value: K300
CALL pr_receive_delivery(
    3,
    'A',
    60,
    DATE '2026-10-07'
);



-- ==========================================================
-- QUESTION 9 (A): SEED DATA CONTINUED
--
-- Update selected deliveries to PAID.
--
-- This ensures that the sample data contains
-- both payment states: TRUE and FALSE.
--
-- The UPDATE trigger also recalculates the
-- correct unit rate and total value.
-- ==========================================================


-- Mark delivery 2 as paid
UPDATE deliveries
SET is_paid = TRUE
WHERE delivery_id = 2;


-- Mark delivery 4 as paid
UPDATE deliveries
SET is_paid = TRUE
WHERE delivery_id = 4;


-- Mark delivery 6 as paid
UPDATE deliveries
SET is_paid = TRUE
WHERE delivery_id = 6;



-- ==========================================================
-- QUESTION 9 (E): VIEW [5 MARKS]
--
-- View: v_farmer_amount_due
--
-- Displays:
-- Farmer number.
-- Farmer name.
-- Total unpaid delivery value.
--
-- Includes farmers with no unpaid deliveries.
-- Their amount due must be zero.
-- ==========================================================

CREATE OR REPLACE VIEW v_farmer_amount_due AS

SELECT

    f.farmer_number,

    f.full_name,

    COALESCE(
        SUM(d.total_value),
        0
    ) AS total_amount_due

FROM farmers f

LEFT JOIN deliveries d

    ON f.farmer_id = d.farmer_id

    AND d.is_paid = FALSE

GROUP BY

    f.farmer_id,

    f.farmer_number,

    f.full_name;


-- Display farmer amounts due
SELECT *
FROM v_farmer_amount_due
ORDER BY farmer_number;



-- ==========================================================
-- QUESTION 9 (F): INDEX [5 MARKS]
--
-- Index: idx_deliveries_farmer_date
--
-- Supports searching for a particular farmer's
-- deliveries between two dates.
-- ==========================================================


-- Create composite index
CREATE INDEX idx_deliveries_farmer_date

ON deliveries (
    farmer_id,
    delivered_on
);


-- Matching query:
-- Retrieve Farmer 1's deliveries between
-- October 1 and October 31, 2026.

SELECT

    delivery_id,

    farmer_id,

    grade,

    weight_kg,

    unit_rate,

    total_value,

    delivered_on,

    is_paid

FROM deliveries

WHERE farmer_id = 1

AND delivered_on >= DATE '2026-10-01'

AND delivered_on < DATE '2026-11-01'

ORDER BY delivered_on;


-- Display execution plan
EXPLAIN

SELECT

    delivery_id,

    farmer_id,

    grade,

    weight_kg,

    unit_rate,

    total_value

FROM deliveries

WHERE farmer_id = 1

AND delivered_on >= DATE '2026-10-01'

AND delivered_on < DATE '2026-11-01'

ORDER BY delivered_on;


-- INDEX JUSTIFICATION:
--
-- The index is created on farmer_id and delivered_on.
--
-- farmer_id is the first column because the query
-- searches for deliveries belonging to a particular farmer.
--
-- delivered_on is the second column because the query
-- searches within a specified date range.
--
-- The composite index supports both conditions
-- and improves retrieval of matching delivery records.



-- ==========================================================
-- QUESTION 9 (G): PROCEDURE [6 MARKS]
--
-- Procedure: pr_refresh_purchases(p_day)
--
-- Calculates the total purchased weight and value
-- for a specified delivery date.
--
-- Stores the results in daily_purchases.
--
-- Repeated execution replaces the existing totals
-- rather than adding them again.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_purchases(
    p_day DATE
)
LANGUAGE plpgsql
AS $$
DECLARE

    v_total_weight NUMERIC(14,2);

    v_total_value NUMERIC(16,2);

BEGIN

    -- Validate purchase date
    IF p_day IS NULL THEN

        RAISE EXCEPTION
        'Purchase date cannot be NULL';

    END IF;


    -- Calculate total purchased weight
    -- and total purchased value for the date.

    SELECT

        COALESCE(
            SUM(weight_kg),
            0
        ),

        COALESCE(
            SUM(total_value),
            0
        )

    INTO

        v_total_weight,

        v_total_value

    FROM deliveries

    WHERE delivered_on = p_day;


    -- Insert daily purchase totals.
    -- If the date already exists, replace the totals.
    -- This prevents duplicate accumulation.

    INSERT INTO daily_purchases (
        purchase_date,
        total_weight,
        total_value
    )

    VALUES (
        p_day,
        v_total_weight,
        v_total_value
    )

    ON CONFLICT (purchase_date)

    DO UPDATE SET

        total_weight = EXCLUDED.total_weight,

        total_value = EXCLUDED.total_value;

END;
$$;



-- ==========================================================
-- QUESTION 9 (G): SCHEDULED JOB USING PG_CRON
--
-- Schedule daily execution at 01:30.
--
-- The job processes the PREVIOUS DAY's deliveries.
--
-- Cron expression:
-- 30 1 * * *
--
-- Requires pg_cron installation and configuration.
-- ==========================================================


-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule daily purchase refresh
SELECT cron.schedule(

    'refresh_daily_maize_purchases',

    '30 1 * * *',

    $job$
        CALL q9.pr_refresh_purchases(
            CURRENT_DATE - 1
        );
    $job$

);


-- Display scheduled jobs
SELECT *
FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 9
-- ==========================================================


-- 1. Display all farmers
SELECT *
FROM farmers
ORDER BY farmer_id;


-- 2. Display all deliveries
SELECT *
FROM deliveries
ORDER BY delivery_id;


-- 3. Test Grade A rate
-- Expected result: K5.00
SELECT fn_maize_rate('A');


-- 4. Test Grade B rate
-- Expected result: K4.00
SELECT fn_maize_rate('B');


-- 5. Test Grade C rate
-- Expected result: K3.00
SELECT fn_maize_rate('C');


-- 6. Test Grade A delivery value
-- 100 kg x K5 = K500
SELECT
    100 AS weight_kg,
    fn_maize_rate('A') AS unit_rate,
    100 * fn_maize_rate('A') AS total_value;


-- 7. Test Grade B delivery value
-- 100 kg x K4 = K400
SELECT
    100 AS weight_kg,
    fn_maize_rate('B') AS unit_rate,
    100 * fn_maize_rate('B') AS total_value;


-- 8. Test Grade C delivery value
-- 100 kg x K3 = K300
SELECT
    100 AS weight_kg,
    fn_maize_rate('C') AS unit_rate,
    100 * fn_maize_rate('C') AS total_value;


-- 9. Display farmer amounts due
SELECT *
FROM v_farmer_amount_due
ORDER BY farmer_number;


-- 10. Manually refresh purchases for October 1
CALL pr_refresh_purchases(
    DATE '2026-10-01'
);


-- 11. Manually refresh purchases for October 2
CALL pr_refresh_purchases(
    DATE '2026-10-02'
);


-- 12. Display daily purchase totals
SELECT *
FROM daily_purchases
ORDER BY purchase_date;


-- 13. Test repeated execution.
-- The totals for October 1 must be replaced,
-- not added to the existing totals.

CALL pr_refresh_purchases(
    DATE '2026-10-01'
);


-- 14. Display totals again
SELECT *
FROM daily_purchases
ORDER BY purchase_date;


-- 15. Test the composite index query
EXPLAIN

SELECT *
FROM deliveries

WHERE farmer_id = 1

AND delivered_on >= DATE '2026-10-01'

AND delivered_on < DATE '2026-11-01';


-- 16. Display scheduled jobs
SELECT *
FROM cron.job;


-- 17. Display scheduled job execution history
SELECT *
FROM cron.job_run_details

WHERE jobid = (
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'refresh_daily_maize_purchases'
)

ORDER BY start_time DESC;


-- ==========================================================
-- END OF QUESTION 9
-- ==========================================================
