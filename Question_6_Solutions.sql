
/*
============================================================
QUESTION 6: MONTHLY PAYROLL PROCESSING
============================================================
*/


-- ==========================================================
-- QUESTION 6 (A): DATABASE AND SEED DATA [6 MARKS]
-- Create employees, payroll and salary_audit tables.
-- Insert active and inactive employees.
-- Prepare payroll data for at least two months.
-- ==========================================================

-- Create a separate schema for Question 6
CREATE SCHEMA IF NOT EXISTS q6;

SET search_path TO q6, public;


-- 1. EMPLOYEES TABLE
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    basic_salary NUMERIC(12,2) NOT NULL
        CHECK (basic_salary >= 0),
    allowance NUMERIC(12,2) NOT NULL
        CHECK (allowance >= 0),
    deduction NUMERIC(12,2) NOT NULL
        CHECK (deduction >= 0),
    active BOOLEAN NOT NULL DEFAULT TRUE
);


-- 2. PAYROLL TABLE
CREATE TABLE payroll (
    payroll_id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    pay_month DATE NOT NULL,
    gross_pay NUMERIC(12,2) NOT NULL
        CHECK (gross_pay >= 0),
    net_pay NUMERIC(12,2) NOT NULL
        CHECK (net_pay >= 0),

    FOREIGN KEY (employee_id)
    REFERENCES employees(employee_id),

    -- One payroll record per employee per month
    UNIQUE (employee_id, pay_month),

    -- Pay month must be the first day of a month
    CHECK (
        EXTRACT(DAY FROM pay_month) = 1
    )
);


-- 3. SALARY AUDIT TABLE
CREATE TABLE salary_audit (
    audit_id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    old_salary NUMERIC(12,2),
    new_salary NUMERIC(12,2),
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (employee_id)
    REFERENCES employees(employee_id)
);


-- Insert five employees
INSERT INTO employees (
    full_name,
    basic_salary,
    allowance,
    deduction,
    active
)
VALUES
('John Banda', 5000, 1000, 500, TRUE),

('Mary Phiri', 6500, 1500, 700, TRUE),

('Peter Zulu', 4000, 800, 300, TRUE),

('Grace Tembo', 7000, 1200, 900, FALSE),

('James Mwale', 5500, 1000, 600, TRUE);



-- ==========================================================
-- QUESTION 6 (B): FUNCTION [6 MARKS]
-- Function: fn_net_pay
-- Calculates an employee's net pay.
--
-- Formula:
-- Gross Pay = Basic Salary + Allowance
-- Net Pay = Gross Pay - Deduction
--
-- Rejects an unknown employee and negative net pay.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_net_pay(
    p_employee_id INTEGER
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_basic_salary NUMERIC(12,2);
    v_allowance NUMERIC(12,2);
    v_deduction NUMERIC(12,2);
    v_net_pay NUMERIC(12,2);
BEGIN

    -- Validate employee ID
    IF p_employee_id IS NULL THEN
        RAISE EXCEPTION
        'Employee ID cannot be NULL';
    END IF;

    -- Retrieve employee salary details
    SELECT
        basic_salary,
        allowance,
        deduction

    INTO
        v_basic_salary,
        v_allowance,
        v_deduction

    FROM employees
    WHERE employee_id = p_employee_id;

    -- Check whether employee exists
    IF NOT FOUND THEN
        RAISE EXCEPTION
        'Employee ID % does not exist',
        p_employee_id;
    END IF;

    -- Calculate net pay
    v_net_pay :=
        v_basic_salary
        + v_allowance
        - v_deduction;

    -- Reject negative net pay
    IF v_net_pay < 0 THEN
        RAISE EXCEPTION
        'Net pay cannot be negative for employee %',
        p_employee_id;
    END IF;

    -- Return calculated net pay
    RETURN v_net_pay;

END;
$$;



-- ==========================================================
-- QUESTION 6 (C): PROCEDURE [8 MARKS]
-- Procedure: pr_process_payroll
--
-- Uses a QUERY FOR LOOP to process active employees.
-- Requires a month-start date.
-- Inserts missing employee/month payroll records.
-- Existing payroll records remain unchanged.
-- An invalid employee calculation fails the whole call.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_process_payroll(
    p_month DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_employee RECORD;
    v_gross_pay NUMERIC(12,2);
    v_net_pay NUMERIC(12,2);
BEGIN

    -- Validate payroll month
    IF p_month IS NULL THEN
        RAISE EXCEPTION
        'Payroll month cannot be NULL';
    END IF;

    -- Ensure the supplied date is the first day of a month
    IF EXTRACT(DAY FROM p_month) <> 1 THEN
        RAISE EXCEPTION
        'Pay month must be the first day of a month';
    END IF;


    -- Loop through all active employees
    FOR v_employee IN

        SELECT
            employee_id,
            basic_salary,
            allowance,
            deduction

        FROM employees
        WHERE active = TRUE
        ORDER BY employee_id

    LOOP

        -- Calculate gross pay
        v_gross_pay :=
            v_employee.basic_salary
            + v_employee.allowance;

        -- Calculate net pay using the function
        v_net_pay := fn_net_pay(
            v_employee.employee_id
        );

        -- Insert payroll record
        -- ON CONFLICT DO NOTHING ensures that an
        -- existing employee/month record is unchanged.
        INSERT INTO payroll (
            employee_id,
            pay_month,
            gross_pay,
            net_pay
        )
        VALUES (
            v_employee.employee_id,
            p_month,
            v_gross_pay,
            v_net_pay
        )

        ON CONFLICT (employee_id, pay_month)
        DO NOTHING;

    END LOOP;

END;
$$;



-- ==========================================================
-- QUESTION 6 (D): TRIGGER [8 MARKS]
-- Trigger: trg_salary_audit
--
-- AFTER UPDATE trigger on employees.
-- Records actual basic_salary changes using OLD and NEW.
-- Does not create an audit entry when salary is unchanged.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_salary_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    -- Check whether basic salary actually changed
    IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN

        -- Record salary change
        INSERT INTO salary_audit (
            employee_id,
            old_salary,
            new_salary,
            changed_at
        )
        VALUES (
            NEW.employee_id,
            OLD.basic_salary,
            NEW.basic_salary,
            CURRENT_TIMESTAMP
        );

    END IF;

    RETURN NEW;

END;
$$;


-- Create AFTER UPDATE trigger
CREATE TRIGGER trg_salary_audit
AFTER UPDATE ON employees
FOR EACH ROW
EXECUTE FUNCTION fn_salary_audit();



-- ==========================================================
-- QUESTION 6 (A): SEED DATA CONTINUED
-- Process payroll for two different months.
-- Only active employees will receive payroll records.
-- ==========================================================

-- Process payroll for the first month
CALL pr_process_payroll(
    DATE '2026-09-01'
);


-- Process payroll for the second month
CALL pr_process_payroll(
    DATE '2026-10-01'
);


-- Display generated payroll records
SELECT * FROM payroll
ORDER BY pay_month, employee_id;



-- ==========================================================
-- QUESTION 6 (E): VIEW [5 MARKS]
-- View: v_payroll_report
--
-- Joins employee names to payroll records.
-- Displays pay_month, gross_pay and net_pay.
-- Includes historical records for employees
-- who later become inactive.
-- ==========================================================

CREATE OR REPLACE VIEW v_payroll_report AS
SELECT
    p.payroll_id,
    e.employee_id,
    e.full_name,
    p.pay_month,
    p.gross_pay,
    p.net_pay

FROM payroll p

JOIN employees e
    ON p.employee_id = e.employee_id;


-- Display payroll report
SELECT *
FROM v_payroll_report
ORDER BY pay_month, employee_id;



-- ==========================================================
-- QUESTION 6 (F): INDEX [5 MARKS]
-- Index: idx_payroll_month
--
-- Supports reports filtered by pay_month
-- across all employees.
--
-- Avoids duplicating the existing UNIQUE index
-- on employee_id and pay_month.
-- ==========================================================

-- Create index on pay_month
CREATE INDEX idx_payroll_month
ON payroll (pay_month);


-- Matching query
SELECT
    payroll_id,
    employee_id,
    pay_month,
    gross_pay,
    net_pay

FROM payroll
WHERE pay_month = DATE '2026-09-01';


-- Display execution plan
EXPLAIN
SELECT
    payroll_id,
    employee_id,
    pay_month,
    gross_pay,
    net_pay

FROM payroll
WHERE pay_month = DATE '2026-09-01';


-- INDEX JUSTIFICATION:
-- The index is created on pay_month because
-- payroll reports search for records belonging
-- to a particular month.
--
-- The existing UNIQUE index on
-- (employee_id, pay_month) is not suitable
-- as a replacement for this month-only index.
--
-- Therefore, a separate index on pay_month
-- supports monthly payroll reports.



-- ==========================================================
-- QUESTION 6 (G): SCHEDULED JOB [6 MARKS]
-- Schedule pr_process_payroll for 02:00
-- on the first day of every month.
--
-- The job processes the first day of the previous month.
-- ==========================================================

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule monthly payroll processing
SELECT cron.schedule(
    'monthly_payroll_processing',
    '0 2 1 * *',
    $job$
        CALL q6.pr_process_payroll(
            (
                DATE_TRUNC('month', CURRENT_DATE)
                - INTERVAL '1 month'
            )::DATE
        );
    $job$
);


-- Display scheduled jobs
SELECT *
FROM cron.job;


-- Display payroll job execution history
SELECT *
FROM cron.job_run_details
WHERE jobid = (
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'monthly_payroll_processing'
)
ORDER BY start_time DESC;



-- ==========================================================
-- FINAL TESTING: QUESTION 6
-- ==========================================================


-- 1. Display all employees
SELECT * FROM employees;


-- 2. Display all payroll records
SELECT *
FROM payroll
ORDER BY pay_month, employee_id;


-- 3. Test net pay for employee 1
SELECT fn_net_pay(1);


-- 4. Test net pay for employee 2
SELECT fn_net_pay(2);


-- 5. Test net pay for employee 3
SELECT fn_net_pay(3);


-- 6. Display the payroll report
SELECT *
FROM v_payroll_report
ORDER BY pay_month, employee_id;


-- 7. Display salary audit records
SELECT * FROM salary_audit;


-- 8. Test salary audit trigger
-- Increase employee 1's basic salary by K500.
UPDATE employees
SET basic_salary = basic_salary + 500
WHERE employee_id = 1;


-- Display the audit record
SELECT * FROM salary_audit;


-- 9. Test that rerunning payroll does not
-- change existing payroll records.
-- Employee 1's September payroll should remain unchanged.

CALL pr_process_payroll(
    DATE '2026-09-01'
);


-- 10. Display payroll after rerunning the procedure
SELECT *
FROM payroll
WHERE pay_month = DATE '2026-09-01'
ORDER BY employee_id;


-- 11. Display payroll for inactive employees.
-- This should return no records for newly generated payroll.
SELECT *
FROM payroll p
JOIN employees e
    ON p.employee_id = e.employee_id
WHERE e.active = FALSE;


-- 12. Display scheduled job
SELECT *
FROM cron.job;


-- 13. Display scheduled job execution history
SELECT *
FROM cron.job_run_details
ORDER BY start_time DESC;


-- ==========================================================
-- END OF QUESTION 6
-- ==========================================================
