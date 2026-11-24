
/*
============================================================
QUESTION 10: SCHOLARSHIP APPLICATION ASSESSMENT
============================================================
*/


-- ==========================================================
-- QUESTION 10 (A): DATABASE AND SEED DATA [6 MARKS]
--
-- Create three tables:
-- 1. students
-- 2. applications
-- 3. decision_audit
--
-- Insert at least three students and six PENDING
-- scholarship applications.
--
-- Applications cover:
-- - Qualifying applicants.
-- - Non-qualifying applicants.
-- - Boundary cases.
-- ==========================================================


-- Create a separate schema for Question 10
CREATE SCHEMA IF NOT EXISTS q10;

SET search_path TO q10, public;


-- 1. STUDENTS TABLE
CREATE TABLE students (

    student_id SERIAL PRIMARY KEY,

    student_number VARCHAR(30) UNIQUE NOT NULL,

    full_name VARCHAR(100) NOT NULL

);


-- 2. APPLICATIONS TABLE
CREATE TABLE applications (

    application_id SERIAL PRIMARY KEY,

    student_id INTEGER NOT NULL,

    age_at_application INTEGER NOT NULL,

    monthly_income NUMERIC(12,2) NOT NULL,

    average_mark NUMERIC(5,2) NOT NULL,

    submitted_on DATE NOT NULL,

    status VARCHAR(10) NOT NULL DEFAULT 'PENDING',

    FOREIGN KEY (student_id)
        REFERENCES students(student_id),

    -- Age must be positive
    CHECK (age_at_application > 0),

    -- Income cannot be negative
    CHECK (monthly_income >= 0),

    -- Marks must be between 0 and 100
    CHECK (average_mark BETWEEN 0 AND 100),

    -- Only three application statuses are allowed
    CHECK (
        status IN ('PENDING', 'APPROVED', 'REJECTED')
    )

);


-- 3. DECISION_AUDIT TABLE
CREATE TABLE decision_audit (

    audit_id SERIAL PRIMARY KEY,

    application_id INTEGER NOT NULL,

    old_status VARCHAR(10) NOT NULL,

    new_status VARCHAR(10) NOT NULL,

    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (application_id)
        REFERENCES applications(application_id)

);


-- Insert three students
INSERT INTO students (
    student_number,
    full_name
)
VALUES

('202404001', 'John Banda'),

('202404002', 'Mary Phiri'),

('202404003', 'Peter Zulu');



-- Insert six scholarship applications.
-- All applications initially have PENDING status.


-- APPLICATION 1:
-- Age: 18
-- Income: K3,000
-- Average mark: 70
-- Boundary case: QUALIFIES.

INSERT INTO applications (
    student_id,
    age_at_application,
    monthly_income,
    average_mark,
    submitted_on
)
VALUES (
    1,
    18,
    3000,
    70,
    DATE '2026-09-01'
);


-- APPLICATION 2:
-- Age: 25
-- Income: K3,000
-- Average mark: 70
-- Boundary case: QUALIFIES.

INSERT INTO applications (
    student_id,
    age_at_application,
    monthly_income,
    average_mark,
    submitted_on
)
VALUES (
    1,
    25,
    3000,
    70,
    DATE '2026-09-02'
);


-- APPLICATION 3:
-- Age: 17
-- Income: K2,000
-- Average mark: 80
-- Does not qualify because age is below 18.

INSERT INTO applications (
    student_id,
    age_at_application,
    monthly_income,
    average_mark,
    submitted_on
)
VALUES (
    2,
    17,
    2000,
    80,
    DATE '2026-09-03'
);


-- APPLICATION 4:
-- Age: 22
-- Income: K3,500
-- Average mark: 85
-- Does not qualify because income exceeds K3,000.

INSERT INTO applications (
    student_id,
    age_at_application,
    monthly_income,
    average_mark,
    submitted_on
)
VALUES (
    2,
    22,
    3500,
    85,
    DATE '2026-09-04'
);


-- APPLICATION 5:
-- Age: 24
-- Income: K2,500
-- Average mark: 69
-- Does not qualify because mark is below 70.

INSERT INTO applications (
    student_id,
    age_at_application,
    monthly_income,
    average_mark,
    submitted_on
)
VALUES (
    3,
    24,
    2500,
    69,
    DATE '2026-09-05'
);


-- APPLICATION 6:
-- Age: 26
-- Income: K1,500
-- Average mark: 90
-- Does not qualify because age exceeds 25.

INSERT INTO applications (
    student_id,
    age_at_application,
    monthly_income,
    average_mark,
    submitted_on
)
VALUES (
    3,
    26,
    1500,
    90,
    DATE '2026-09-06'
);



-- ==========================================================
-- QUESTION 10 (B): FUNCTION [6 MARKS]
--
-- Function: fn_scholarship_eligible()
--
-- Parameters:
-- p_age
-- p_income
-- p_mark
--
-- Returns TRUE when all three eligibility conditions
-- are satisfied.
--
-- Eligibility:
-- Age: 18 to 25 inclusive.
-- Income: At most K3,000.
-- Average mark: At least 70.
--
-- Rejects NULL and invalid inputs.
-- ==========================================================


CREATE OR REPLACE FUNCTION fn_scholarship_eligible(

    p_age INTEGER,

    p_income NUMERIC,

    p_mark NUMERIC

)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN

    -- Reject NULL age
    IF p_age IS NULL THEN

        RAISE EXCEPTION
        'Applicant age cannot be NULL';

    END IF;


    -- Reject NULL income
    IF p_income IS NULL THEN

        RAISE EXCEPTION
        'Monthly household income cannot be NULL';

    END IF;


    -- Reject NULL average mark
    IF p_mark IS NULL THEN

        RAISE EXCEPTION
        'Average mark cannot be NULL';

    END IF;


    -- Age must be positive
    IF p_age <= 0 THEN

        RAISE EXCEPTION
        'Applicant age must be positive';

    END IF;


    -- Income cannot be negative
    IF p_income < 0 THEN

        RAISE EXCEPTION
        'Monthly household income cannot be negative';

    END IF;


    -- Marks must be between 0 and 100
    IF p_mark < 0 OR p_mark > 100 THEN

        RAISE EXCEPTION
        'Average mark must be between 0 and 100';

    END IF;


    -- Check all three scholarship requirements
    IF p_age BETWEEN 18 AND 25

       AND p_income <= 3000

       AND p_mark >= 70 THEN

        RETURN TRUE;

    ELSE

        RETURN FALSE;

    END IF;

END;
$$;



-- ==========================================================
-- QUESTION 10 (C): PROCEDURE [8 MARKS]
--
-- Procedure: pr_assess_application()
--
-- Accepts an application ID.
--
-- Responsibilities:
-- 1. Check whether the application exists.
-- 2. Ensure its status is PENDING.
-- 3. Retrieve the applicant's information.
-- 4. Call fn_scholarship_eligible().
-- 5. Update status to APPROVED or REJECTED.
--
-- Raises an exception for unknown or already
-- assessed applications.
-- ==========================================================


CREATE OR REPLACE PROCEDURE pr_assess_application(

    p_application_id INTEGER

)
LANGUAGE plpgsql
AS $$
DECLARE

    v_age INTEGER;

    v_income NUMERIC(12,2);

    v_mark NUMERIC(5,2);

    v_status VARCHAR(10);

    v_eligible BOOLEAN;

BEGIN

    -- Validate application ID
    IF p_application_id IS NULL THEN

        RAISE EXCEPTION
        'Application ID cannot be NULL';

    END IF;


    -- Retrieve application details and lock the row.
    -- FOR UPDATE prevents simultaneous assessment
    -- of the same application.

    SELECT

        age_at_application,

        monthly_income,

        average_mark,

        status

    INTO

        v_age,

        v_income,

        v_mark,

        v_status

    FROM applications

    WHERE application_id = p_application_id

    FOR UPDATE;


    -- Check whether application exists
    IF NOT FOUND THEN

        RAISE EXCEPTION
        'Application ID % does not exist',
        p_application_id;

    END IF;


    -- Only PENDING applications can be assessed
    IF v_status <> 'PENDING' THEN

        RAISE EXCEPTION
        'Application ID % has already been assessed. Current status: %',
        p_application_id,
        v_status;

    END IF;


    -- Call eligibility function
    v_eligible := fn_scholarship_eligible(

        v_age,

        v_income,

        v_mark

    );


    -- Update application status based on eligibility
    IF v_eligible = TRUE THEN

        UPDATE applications

        SET status = 'APPROVED'

        WHERE application_id = p_application_id;

    ELSE

        UPDATE applications

        SET status = 'REJECTED'

        WHERE application_id = p_application_id;

    END IF;


END;
$$;



-- ==========================================================
-- QUESTION 10 (D): TRIGGER [8 MARKS]
--
-- Trigger: trg_audit_application_decision
--
-- AFTER UPDATE row trigger on applications.
--
-- Responsibilities:
-- 1. Detect changes in application status.
-- 2. Record the old status.
-- 3. Record the new status.
-- 4. Record the date and time of the change.
--
-- An unchanged status must NOT create an audit record.
-- ==========================================================


-- Create trigger function
CREATE OR REPLACE FUNCTION fn_audit_application_decision()

RETURNS TRIGGER

LANGUAGE plpgsql
AS $$
BEGIN

    -- Record only actual status changes
    IF OLD.status IS DISTINCT FROM NEW.status THEN

        INSERT INTO decision_audit (

            application_id,

            old_status,

            new_status,

            changed_at

        )

        VALUES (

            NEW.application_id,

            OLD.status,

            NEW.status,

            CURRENT_TIMESTAMP

        );

    END IF;


    -- Return updated application
    RETURN NEW;

END;
$$;


-- Create AFTER UPDATE trigger
-- The WHEN condition ensures that unchanged
-- statuses do not create audit entries.

CREATE TRIGGER trg_audit_application_decision

AFTER UPDATE ON applications

FOR EACH ROW

WHEN (OLD.status IS DISTINCT FROM NEW.status)

EXECUTE FUNCTION fn_audit_application_decision();



-- ==========================================================
-- QUESTION 10 (E): VIEW [5 MARKS]
--
-- View: v_approved_applicants
--
-- Displays:
-- Student number.
-- Full name.
-- Average mark.
-- Application status.
--
-- Includes APPROVED applications only.
--
-- Household income must NOT be displayed.
-- ==========================================================


CREATE OR REPLACE VIEW v_approved_applicants AS

SELECT

    s.student_number,

    s.full_name,

    a.average_mark,

    a.status

FROM applications a

JOIN students s

    ON a.student_id = s.student_id

WHERE a.status = 'APPROVED';


-- Display approved scholarship applicants
SELECT *

FROM v_approved_applicants

ORDER BY student_number;



-- ==========================================================
-- QUESTION 10 (F): INDEX [5 MARKS]
--
-- Index: idx_applications_status_date
--
-- Supports searching for applications by status
-- within a submitted_on date range.
-- ==========================================================


-- Create composite index
CREATE INDEX idx_applications_status_date

ON applications (

    status,

    submitted_on

);


-- Matching query:
-- Retrieve PENDING applications submitted
-- between September 1 and September 30, 2026.

SELECT

    application_id,

    student_id,

    age_at_application,

    average_mark,

    submitted_on,

    status

FROM applications

WHERE status = 'PENDING'

AND submitted_on >= DATE '2026-09-01'

AND submitted_on < DATE '2026-10-01'

ORDER BY submitted_on;


-- Display execution plan
EXPLAIN

SELECT

    application_id,

    student_id,

    age_at_application,

    average_mark,

    submitted_on,

    status

FROM applications

WHERE status = 'PENDING'

AND submitted_on >= DATE '2026-09-01'

AND submitted_on < DATE '2026-10-01'

ORDER BY submitted_on;


-- INDEX JUSTIFICATION:
--
-- The index is created on status and submitted_on.
--
-- status is the first column because the query
-- searches for applications with a particular status.
--
-- submitted_on is the second column because the query
-- searches within a specified submission date range.
--
-- The composite index supports both conditions
-- and improves retrieval of matching applications.



-- ==========================================================
-- QUESTION 10 (G): PROCEDURE [6 MARKS]
--
-- Procedure: pr_assess_pending()
--
-- Uses a QUERY FOR LOOP to process applications
-- that are still PENDING.
--
-- Calls pr_assess_application() for each application.
--
-- Only PENDING applications are processed.
--
-- Completed applications are not reassessed.
-- Repeated execution does not create duplicate
-- audit entries.
-- ==========================================================


CREATE OR REPLACE PROCEDURE pr_assess_pending()

LANGUAGE plpgsql

AS $$
DECLARE

    v_application RECORD;

BEGIN

    -- Loop through all pending applications
    FOR v_application IN

        SELECT application_id

        FROM applications

        WHERE status = 'PENDING'

        ORDER BY application_id

    LOOP

        -- Assess each pending application
        CALL pr_assess_application(

            v_application.application_id

        );

    END LOOP;


END;
$$;



-- ==========================================================
-- QUESTION 10 (G): SCHEDULED JOB USING PG_CRON
--
-- Schedule automatic scholarship assessment
-- every Monday at 08:00.
--
-- Cron expression:
-- 0 8 * * 1
--
-- Requires pg_cron installation and configuration.
-- ==========================================================


-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule weekly scholarship assessment
SELECT cron.schedule(

    'assess_pending_scholarships',

    '0 8 * * 1',

    'CALL q10.pr_assess_pending();'

);


-- Display scheduled jobs
SELECT *

FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 10
-- ==========================================================


-- 1. Display all students
SELECT *

FROM students

ORDER BY student_id;


-- 2. Display all scholarship applications
SELECT *

FROM applications

ORDER BY application_id;


-- 3. Test the eligibility function.
-- Expected result: TRUE
SELECT fn_scholarship_eligible(
    18,
    3000,
    70
);


-- 4. Test the eligibility function.
-- Expected result: TRUE
SELECT fn_scholarship_eligible(
    25,
    3000,
    70
);


-- 5. Test the eligibility function.
-- Expected result: FALSE (age below 18)
SELECT fn_scholarship_eligible(
    17,
    2000,
    80
);


-- 6. Test the eligibility function.
-- Expected result: FALSE (income above K3,000)
SELECT fn_scholarship_eligible(
    22,
    3500,
    85
);


-- 7. Test the eligibility function.
-- Expected result: FALSE (mark below 70)
SELECT fn_scholarship_eligible(
    24,
    2500,
    69
);


-- 8. Test the eligibility function.
-- Expected result: FALSE (age above 25)
SELECT fn_scholarship_eligible(
    26,
    1500,
    90
);


-- 9. Manually assess application 1.
-- Expected result: APPROVED.

CALL pr_assess_application(1);


-- 10. Display application 1
SELECT *

FROM applications

WHERE application_id = 1;


-- 11. Display audit records.
-- One record should exist for application 1.

SELECT *

FROM decision_audit

ORDER BY audit_id;


-- 12. Assess all remaining pending applications.
-- Application 1 will not be reassessed.

CALL pr_assess_pending();


-- 13. Display all assessed applications.
SELECT *

FROM applications

ORDER BY application_id;


-- 14. Display all audit records.
SELECT *

FROM decision_audit

ORDER BY audit_id;


-- 15. Display approved applicants.
SELECT *

FROM v_approved_applicants

ORDER BY student_number;


-- 16. Test the index query.
EXPLAIN

SELECT *

FROM applications

WHERE status = 'PENDING'

AND submitted_on >= DATE '2026-09-01'

AND submitted_on < DATE '2026-10-01';


-- 17. Run the assessment procedure again.
-- No completed application should be reassessed.
-- No duplicate audit entries should be created.

CALL pr_assess_pending();


-- 18. Display applications after rerunning.
SELECT *

FROM applications

ORDER BY application_id;


-- 19. Display audit records after rerunning.
SELECT *

FROM decision_audit

ORDER BY audit_id;


-- 20. Display scheduled jobs.
SELECT *

FROM cron.job;


-- 21. Display scheduled job execution history.
SELECT *

FROM cron.job_run_details

WHERE jobid = (

    SELECT jobid

    FROM cron.job

    WHERE jobname = 'assess_pending_scholarships'

)

ORDER BY start_time DESC;


-- ==========================================================
-- END OF QUESTION 10
-- ==========================================================
