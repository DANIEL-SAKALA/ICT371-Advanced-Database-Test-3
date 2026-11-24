
/*
============================================================
QUESTION 4: CLINIC APPOINTMENT SCHEDULING
============================================================
*/


-- ==========================================================
-- QUESTION 4 (A): DATABASE AND SEED DATA [6 MARKS]
-- Create four tables.
-- Prepare three patients, three doctors and six appointments.
-- ==========================================================

-- Create a separate schema for Question 4
CREATE SCHEMA IF NOT EXISTS q4;

SET search_path TO q4, public;


-- 1. PATIENTS TABLE
CREATE TABLE patients (
    patient_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);


-- 2. DOCTORS TABLE
CREATE TABLE doctors (
    doctor_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);


-- 3. APPOINTMENTS TABLE
CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL,
    doctor_id INTEGER NOT NULL,
    appointment_day DATE NOT NULL,
    slot_time TIME NOT NULL,
    status VARCHAR(20) NOT NULL,

    FOREIGN KEY (patient_id)
    REFERENCES patients(patient_id),

    FOREIGN KEY (doctor_id)
    REFERENCES doctors(doctor_id),

    CHECK (
        status IN ('BOOKED', 'ATTENDED', 'CANCELLED')
    )
);


-- 4. CLINIC SUMMARY TABLE
CREATE TABLE clinic_summary (
    summary_date DATE PRIMARY KEY,
    booked_count INTEGER NOT NULL,
    attended_count INTEGER NOT NULL,
    cancelled_count INTEGER NOT NULL
);


-- Insert three patients
INSERT INTO patients (full_name)
VALUES
('John Banda'),
('Mary Phiri'),
('Peter Zulu');


-- Insert three doctors
INSERT INTO doctors (full_name)
VALUES
('Dr. James Mwale'),
('Dr. Grace Tembo'),
('Dr. Sarah Chanda');



-- ==========================================================
-- QUESTION 4 (B): FUNCTION [6 MARKS]
-- Function: fn_daily_load
-- Returns the number of non-cancelled appointments
-- for a particular doctor on a given day.
-- Rejects an unknown doctor.
-- Returns zero when there are no bookings.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_daily_load(
    p_doctor_id INTEGER,
    p_day DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN

    -- Validate doctor ID
    IF p_doctor_id IS NULL THEN
        RAISE EXCEPTION 'Doctor ID cannot be NULL';
    END IF;

    -- Validate appointment date
    IF p_day IS NULL THEN
        RAISE EXCEPTION 'Appointment date cannot be NULL';
    END IF;

    -- Check whether doctor exists
    IF NOT EXISTS (
        SELECT 1
        FROM doctors
        WHERE doctor_id = p_doctor_id
    ) THEN
        RAISE EXCEPTION
        'Doctor ID % does not exist',
        p_doctor_id;
    END IF;

    -- Count non-cancelled appointments
    SELECT COUNT(*)::INTEGER
    INTO v_count
    FROM appointments
    WHERE doctor_id = p_doctor_id
    AND appointment_day = p_day
    AND status <> 'CANCELLED';

    -- Return appointment count
    RETURN v_count;

END;
$$;



-- ==========================================================
-- QUESTION 4 (C): PROCEDURE [8 MARKS]
-- Procedure: pr_book_appointment
-- Validates patient, doctor, date and appointment slot.
-- Inserts a new appointment with BOOKED status.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_book_appointment(
    p_patient_id INTEGER,
    p_doctor_id INTEGER,
    p_day DATE,
    p_slot TIME
)
LANGUAGE plpgsql
AS $$
BEGIN

    -- Validate patient ID
    IF p_patient_id IS NULL THEN
        RAISE EXCEPTION 'Patient ID cannot be NULL';
    END IF;

    -- Validate doctor ID
    IF p_doctor_id IS NULL THEN
        RAISE EXCEPTION 'Doctor ID cannot be NULL';
    END IF;

    -- Validate appointment date
    IF p_day IS NULL THEN
        RAISE EXCEPTION 'Appointment date cannot be NULL';
    END IF;

    -- Validate appointment slot
    IF p_slot IS NULL THEN
        RAISE EXCEPTION 'Appointment slot cannot be NULL';
    END IF;

    -- Check whether patient exists
    IF NOT EXISTS (
        SELECT 1
        FROM patients
        WHERE patient_id = p_patient_id
    ) THEN
        RAISE EXCEPTION
        'Patient ID % does not exist',
        p_patient_id;
    END IF;

    -- Check whether doctor exists
    IF NOT EXISTS (
        SELECT 1
        FROM doctors
        WHERE doctor_id = p_doctor_id
    ) THEN
        RAISE EXCEPTION
        'Doctor ID % does not exist',
        p_doctor_id;
    END IF;

    -- Reject past appointment dates
    IF p_day < CURRENT_DATE THEN
        RAISE EXCEPTION
        'Cannot book an appointment for a past date';
    END IF;

    -- Only four appointment slots are allowed
    IF p_slot NOT IN (
        TIME '09:00',
        TIME '10:00',
        TIME '11:00',
        TIME '12:00'
    ) THEN
        RAISE EXCEPTION
        'Unsupported appointment slot. Allowed slots are 09:00, 10:00, 11:00 and 12:00';
    END IF;

    -- Insert the appointment
    -- The trigger will check for slot clashes.
    INSERT INTO appointments (
        patient_id,
        doctor_id,
        appointment_day,
        slot_time,
        status
    )
    VALUES (
        p_patient_id,
        p_doctor_id,
        p_day,
        p_slot,
        'BOOKED'
    );

END;
$$;



-- ==========================================================
-- QUESTION 4 (D): TRIGGER [8 MARKS]
-- Trigger: trg_check_appointment_clash
-- BEFORE INSERT OR UPDATE trigger.
-- Rejects duplicate non-cancelled appointments
-- for the same doctor, date and slot.
-- Excludes the current appointment during UPDATE.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_check_appointment_clash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    -- Only non-cancelled appointments need clash checking
    IF NEW.status <> 'CANCELLED' THEN

        -- Serialize changes for the same doctor and date.
        -- This also protects against simultaneous bookings.
        PERFORM pg_advisory_xact_lock(
            NEW.doctor_id,
            (NEW.appointment_day - DATE '2000-01-01')
        );

        -- Check whether another active appointment
        -- already occupies the same slot.
        IF EXISTS (
            SELECT 1
            FROM appointments
            WHERE doctor_id = NEW.doctor_id
            AND appointment_day = NEW.appointment_day
            AND slot_time = NEW.slot_time
            AND status <> 'CANCELLED'

            -- Exclude the appointment being updated
            AND appointment_id IS DISTINCT FROM NEW.appointment_id
        ) THEN

            RAISE EXCEPTION
            'Appointment clash: Doctor %, date % and slot % are already occupied',
            NEW.doctor_id,
            NEW.appointment_day,
            NEW.slot_time;

        END IF;

    END IF;

    RETURN NEW;

END;
$$;


-- Create BEFORE INSERT OR UPDATE trigger
CREATE TRIGGER trg_check_appointment_clash
BEFORE INSERT OR UPDATE ON appointments
FOR EACH ROW
EXECUTE FUNCTION fn_check_appointment_clash();



-- ==========================================================
-- QUESTION 4 (A): SEED DATA CONTINUED
-- Insert six appointments.
-- Use different slots to avoid appointment clashes.
-- ==========================================================

-- Doctor 1 appointments
CALL pr_book_appointment(
    1, 1, CURRENT_DATE, TIME '09:00'
);

-- Doctor 1, different slot
CALL pr_book_appointment(
    2, 1, CURRENT_DATE, TIME '10:00'
);


-- Doctor 2 appointments
CALL pr_book_appointment(
    3, 2, CURRENT_DATE, TIME '09:00'
);

-- Doctor 2, different slot
CALL pr_book_appointment(
    1, 2, CURRENT_DATE, TIME '11:00'
);


-- Doctor 3 appointments
CALL pr_book_appointment(
    2, 3, CURRENT_DATE, TIME '10:00'
);

-- Doctor 3, different slot
CALL pr_book_appointment(
    3, 3, CURRENT_DATE, TIME '12:00'
);


-- Update some appointments to demonstrate all statuses.
UPDATE appointments
SET status = 'ATTENDED'
WHERE appointment_id IN (2, 6);

UPDATE appointments
SET status = 'CANCELLED'
WHERE appointment_id = 4;



-- ==========================================================
-- QUESTION 4 (E): VIEW [5 MARKS]
-- View: v_today_appointments
-- Shows today's BOOKED appointments only.
-- Displays patient name, doctor name and appointment slot.
-- Does not expose unrelated patient information.
-- ==========================================================

CREATE OR REPLACE VIEW v_today_appointments AS
SELECT
    a.appointment_day,
    p.full_name AS patient_name,
    d.full_name AS doctor_name,
    a.slot_time
FROM appointments a
JOIN patients p
    ON a.patient_id = p.patient_id
JOIN doctors d
    ON a.doctor_id = d.doctor_id
WHERE a.appointment_day = CURRENT_DATE
AND a.status = 'BOOKED';


-- Display today's booked appointments
SELECT * FROM v_today_appointments;



-- ==========================================================
-- QUESTION 4 (F): INDEX [5 MARKS]
-- Index: idx_appointments_day_doctor
-- Supports searches by appointment date and doctor ID.
-- ==========================================================

-- Create non-unique composite index
CREATE INDEX idx_appointments_day_doctor
ON appointments (appointment_day, doctor_id);


-- Matching query
SELECT *
FROM appointments
WHERE appointment_day = CURRENT_DATE
AND doctor_id = 1;


-- Display execution plan
EXPLAIN
SELECT *
FROM appointments
WHERE appointment_day = CURRENT_DATE
AND doctor_id = 1;


-- INDEX JUSTIFICATION:
-- appointment_day is the first column because
-- the query searches for appointments on a particular day.
--
-- doctor_id is the second column because the query
-- also filters appointments belonging to a particular doctor.
--
-- The index is non-unique because a doctor can have
-- multiple appointments on the same day.



-- ==========================================================
-- QUESTION 4 (G): SCHEDULED JOB [6 MARKS]
-- Procedure: pr_refresh_clinic_summary
-- Counts BOOKED, ATTENDED and CANCELLED appointments
-- for a particular appointment date.
-- Replaces an existing summary when rerun.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(
    p_day DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_booked INTEGER;
    v_attended INTEGER;
    v_cancelled INTEGER;
BEGIN

    -- Validate summary date
    IF p_day IS NULL THEN
        RAISE EXCEPTION
        'Summary date cannot be NULL';
    END IF;

    -- Count each appointment status separately
    SELECT
        COUNT(*) FILTER (
            WHERE status = 'BOOKED'
        )::INTEGER,

        COUNT(*) FILTER (
            WHERE status = 'ATTENDED'
        )::INTEGER,

        COUNT(*) FILTER (
            WHERE status = 'CANCELLED'
        )::INTEGER

    INTO
        v_booked,
        v_attended,
        v_cancelled

    FROM appointments
    WHERE appointment_day = p_day;


    -- Insert or replace the daily clinic summary
    INSERT INTO clinic_summary (
        summary_date,
        booked_count,
        attended_count,
        cancelled_count
    )
    VALUES (
        p_day,
        v_booked,
        v_attended,
        v_cancelled
    )

    ON CONFLICT (summary_date)
    DO UPDATE SET
        booked_count = EXCLUDED.booked_count,
        attended_count = EXCLUDED.attended_count,
        cancelled_count = EXCLUDED.cancelled_count;

END;
$$;


-- Manually test the summary procedure
CALL pr_refresh_clinic_summary(CURRENT_DATE);


-- Display clinic summary
SELECT * FROM clinic_summary;



-- ==========================================================
-- QUESTION 4 (G): SCHEDULED JOB USING PG_CRON
-- Schedule daily execution at 01:00.
-- Process the previous day's appointments.
-- Requires pg_cron installation and configuration.
-- ==========================================================

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule the procedure to run daily at 01:00
SELECT cron.schedule(
    'refresh_clinic_summary',
    '0 1 * * *',
    'CALL q4.pr_refresh_clinic_summary(CURRENT_DATE - 1);'
);


-- Display scheduled jobs
SELECT * FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 4
-- ==========================================================

-- 1. Display all patients
SELECT * FROM patients;


-- 2. Display all doctors
SELECT * FROM doctors;


-- 3. Display all appointments
SELECT * FROM appointments;


-- 4. Display today's booked appointments
SELECT * FROM v_today_appointments;


-- 5. Test daily load for Doctor 1
SELECT fn_daily_load(1, CURRENT_DATE);


-- 6. Test daily load for Doctor 2
SELECT fn_daily_load(2, CURRENT_DATE);


-- 7. Test daily load for Doctor 3
SELECT fn_daily_load(3, CURRENT_DATE);


-- 8. Test a doctor with no appointments on another day
SELECT fn_daily_load(1, CURRENT_DATE + 1);


-- 9. Display clinic summary
SELECT * FROM clinic_summary;


-- 10. Refresh today's clinic summary
CALL pr_refresh_clinic_summary(CURRENT_DATE);


-- 11. Display updated clinic summary
SELECT * FROM clinic_summary;


-- ==========================================================
-- END OF QUESTION 4
-- ==========================================================
