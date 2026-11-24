
/*
============================================================
QUESTION 8: TRANSPORT FLEET MAINTENANCE
============================================================
*/


-- ==========================================================
-- QUESTION 8 (A): DATABASE AND SEED DATA [6 MARKS]
--
-- Create three tables:
-- 1. vehicles
-- 2. trips
-- 3. service_alerts
--
-- Prepare three vehicles and six trips.
-- Trips will be inserted after the trigger is installed.
-- ==========================================================

-- Create a separate schema for Question 8
CREATE SCHEMA IF NOT EXISTS q8;

SET search_path TO q8, public;


-- 1. VEHICLES TABLE
CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY,

    registration VARCHAR(30) UNIQUE NOT NULL,

    current_odometer NUMERIC(12,2) NOT NULL,

    last_service_odometer NUMERIC(12,2) NOT NULL,

    -- Odometers cannot be negative
    CHECK (current_odometer >= 0),

    CHECK (last_service_odometer >= 0),

    -- Last service odometer cannot exceed
    -- the current odometer.
    CHECK (
        last_service_odometer <= current_odometer
    )
);


-- 2. TRIPS TABLE
CREATE TABLE trips (
    trip_id SERIAL PRIMARY KEY,

    vehicle_id INTEGER NOT NULL,

    trip_on DATE NOT NULL,

    start_odometer NUMERIC(12,2) NOT NULL,

    end_odometer NUMERIC(12,2) NOT NULL,

    FOREIGN KEY (vehicle_id)
    REFERENCES vehicles(vehicle_id),

    CHECK (start_odometer >= 0),

    CHECK (end_odometer >= 0),

    -- End odometer must be greater than start odometer
    CHECK (end_odometer > start_odometer)
);


-- 3. SERVICE_ALERTS TABLE
CREATE TABLE service_alerts (
    vehicle_id INTEGER PRIMARY KEY,

    km_since_service NUMERIC(12,2) NOT NULL,

    flagged_on DATE NOT NULL,

    FOREIGN KEY (vehicle_id)
    REFERENCES vehicles(vehicle_id),

    CHECK (km_since_service >= 5000)
);


-- Insert three vehicles.
-- Each vehicle has a different service position.

INSERT INTO vehicles (
    registration,
    current_odometer,
    last_service_odometer
)
VALUES

-- Vehicle 1: 4,000 km since last service
('BCA 1234', 100000, 96000),

-- Vehicle 2: 6,000 km since last service
('BCD 5678', 200000, 194000),

-- Vehicle 3: 5,000 km since last service
('BCE 9012', 50000, 45000);



-- ==========================================================
-- QUESTION 8 (B): FUNCTION [6 MARKS]
--
-- Function: fn_service_due(p_vehicle_id)
--
-- Returns TRUE if a vehicle has travelled
-- at least 5,000 kilometres since its last service.
--
-- Returns FALSE if it has travelled less than
-- 5,000 kilometres.
--
-- Rejects an unknown vehicle.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_service_due(
    p_vehicle_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_odometer NUMERIC(12,2);
    v_last_service_odometer NUMERIC(12,2);
    v_km_since_service NUMERIC(12,2);
BEGIN

    -- Validate vehicle ID
    IF p_vehicle_id IS NULL THEN
        RAISE EXCEPTION
        'Vehicle ID cannot be NULL';
    END IF;

    -- Retrieve vehicle odometer details
    SELECT
        current_odometer,
        last_service_odometer

    INTO
        v_current_odometer,
        v_last_service_odometer

    FROM vehicles
    WHERE vehicle_id = p_vehicle_id;

    -- Reject unknown vehicle
    IF NOT FOUND THEN
        RAISE EXCEPTION
        'Vehicle ID % does not exist',
        p_vehicle_id;
    END IF;

    -- Calculate kilometres since last service
    v_km_since_service :=
        v_current_odometer - v_last_service_odometer;

    -- Check the 5,000 kilometre threshold
    IF v_km_since_service >= 5000 THEN

        RETURN TRUE;

    ELSE

        RETURN FALSE;

    END IF;

END;
$$;



-- ==========================================================
-- QUESTION 8 (C): PROCEDURE [8 MARKS]
--
-- Procedure: pr_record_trip
--
-- Parameters:
-- p_vehicle_id
-- p_trip_on
-- p_start
-- p_end
--
-- Validates the vehicle.
-- Requires end odometer to be greater than start odometer.
-- Inserts the trip.
--
-- IMPORTANT:
-- This procedure DOES NOT update current_odometer.
-- The trigger handles that responsibility.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_record_trip(
    p_vehicle_id INTEGER,
    p_trip_on DATE,
    p_start NUMERIC,
    p_end NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN

    -- Validate vehicle ID
    IF p_vehicle_id IS NULL THEN
        RAISE EXCEPTION
        'Vehicle ID cannot be NULL';
    END IF;

    -- Validate trip date
    IF p_trip_on IS NULL THEN
        RAISE EXCEPTION
        'Trip date cannot be NULL';
    END IF;

    -- Validate start odometer
    IF p_start IS NULL OR p_start < 0 THEN
        RAISE EXCEPTION
        'Start odometer must be non-negative';
    END IF;

    -- Validate end odometer
    IF p_end IS NULL OR p_end < 0 THEN
        RAISE EXCEPTION
        'End odometer must be non-negative';
    END IF;

    -- Ensure end odometer is greater than start
    IF p_end <= p_start THEN
        RAISE EXCEPTION
        'End odometer must be greater than start odometer';
    END IF;

    -- Check whether vehicle exists
    IF NOT EXISTS (
        SELECT 1
        FROM vehicles
        WHERE vehicle_id = p_vehicle_id
    ) THEN

        RAISE EXCEPTION
        'Vehicle ID % does not exist',
        p_vehicle_id;

    END IF;

    -- Insert the trip.
    -- The BEFORE INSERT trigger will verify
    -- the starting odometer and update the vehicle.
    INSERT INTO trips (
        vehicle_id,
        trip_on,
        start_odometer,
        end_odometer
    )
    VALUES (
        p_vehicle_id,
        p_trip_on,
        p_start,
        p_end
    );

END;
$$;



-- ==========================================================
-- QUESTION 8 (D): TRIGGER [8 MARKS]
--
-- Trigger: trg_update_vehicle_odometer
--
-- BEFORE INSERT trigger on trips.
--
-- Responsibilities:
-- 1. Verify that start_odometer matches the
--    vehicle's current_odometer.
-- 2. Reject invalid mileage.
-- 3. Update current_odometer to end_odometer.
--
-- The update happens exactly once for each
-- successfully inserted trip.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_update_vehicle_odometer()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_odometer NUMERIC(12,2);
BEGIN

    -- Validate odometer values
    IF NEW.start_odometer IS NULL
       OR NEW.end_odometer IS NULL THEN

        RAISE EXCEPTION
        'Odometer readings cannot be NULL';

    END IF;

    -- Reject negative mileage
    IF NEW.start_odometer < 0
       OR NEW.end_odometer < 0 THEN

        RAISE EXCEPTION
        'Odometer readings cannot be negative';

    END IF;

    -- End must be greater than start
    IF NEW.end_odometer <= NEW.start_odometer THEN

        RAISE EXCEPTION
        'End odometer must be greater than start odometer';

    END IF;

    -- Retrieve and lock the vehicle record.
    -- FOR UPDATE prevents simultaneous trips from
    -- using the same starting odometer.
    SELECT current_odometer
    INTO v_current_odometer

    FROM vehicles

    WHERE vehicle_id = NEW.vehicle_id

    FOR UPDATE;

    -- Check whether vehicle exists
    IF NOT FOUND THEN

        RAISE EXCEPTION
        'Vehicle ID % does not exist',
        NEW.vehicle_id;

    END IF;

    -- Verify starting odometer matches
    -- the vehicle's current odometer.
    IF NEW.start_odometer <> v_current_odometer THEN

        RAISE EXCEPTION
        'Invalid starting odometer. Vehicle current reading is %, but supplied reading is %',
        v_current_odometer,
        NEW.start_odometer;

    END IF;

    -- Update vehicle current odometer.
    -- This happens only once through this trigger.
    UPDATE vehicles

    SET current_odometer = NEW.end_odometer

    WHERE vehicle_id = NEW.vehicle_id;

    -- Allow trip insertion
    RETURN NEW;

END;
$$;


-- Create BEFORE INSERT row trigger
CREATE TRIGGER trg_update_vehicle_odometer

BEFORE INSERT ON trips

FOR EACH ROW

EXECUTE FUNCTION fn_update_vehicle_odometer();



-- ==========================================================
-- QUESTION 8 (A): SEED DATA CONTINUED
--
-- Add six trips using the procedure.
-- The trigger has already been installed.
--
-- Each trip starts at the vehicle's latest
-- current odometer reading.
-- ==========================================================


-- VEHICLE 1: BCA 1234
-- Initial odometer: 100,000
-- Last service: 96,000

-- Trip 1:
-- Start: 100,000
-- End: 100,800
-- Distance: 800 km

CALL pr_record_trip(
    1,
    DATE '2026-09-01',
    100000,
    100800
);


-- Trip 2:
-- Start must match updated current odometer: 100,800
-- End: 101,500
-- Distance: 700 km

CALL pr_record_trip(
    1,
    DATE '2026-09-05',
    100800,
    101500
);


-- VEHICLE 2: BCD 5678
-- Initial odometer: 200,000
-- Last service: 194,000

-- Trip 3:
-- Start: 200,000
-- End: 200,500
-- Distance: 500 km

CALL pr_record_trip(
    2,
    DATE '2026-09-02',
    200000,
    200500
);


-- Trip 4:
-- Start: 200,500
-- End: 201,000
-- Distance: 500 km

CALL pr_record_trip(
    2,
    DATE '2026-09-06',
    200500,
    201000
);


-- VEHICLE 3: BCE 9012
-- Initial odometer: 50,000
-- Last service: 45,000

-- Trip 5:
-- Start: 50,000
-- End: 50,200
-- Distance: 200 km

CALL pr_record_trip(
    3,
    DATE '2026-09-03',
    50000,
    50200
);


-- Trip 6:
-- Start: 50,200
-- End: 50,400
-- Distance: 200 km

CALL pr_record_trip(
    3,
    DATE '2026-09-07',
    50200,
    50400
);



-- ==========================================================
-- QUESTION 8 (E): VIEW [5 MARKS]
--
-- View: v_service_due
--
-- Shows:
-- Vehicle registration.
-- Kilometres travelled since last service.
--
-- Displays only vehicles that have travelled
-- at least 5,000 kilometres since their last service.
-- ==========================================================

CREATE OR REPLACE VIEW v_service_due AS

SELECT
    registration,

    (current_odometer - last_service_odometer)
        AS km_since_service

FROM vehicles

WHERE (
    current_odometer - last_service_odometer
) >= 5000;


-- Display vehicles due for servicing
SELECT *
FROM v_service_due
ORDER BY registration;



-- ==========================================================
-- QUESTION 8 (F): INDEX [5 MARKS]
--
-- Index: idx_trips_vehicle_date
--
-- Supports searching for one vehicle's trips
-- within a specific trip_on date range.
-- ==========================================================

-- Create composite index
CREATE INDEX idx_trips_vehicle_date

ON trips (
    vehicle_id,
    trip_on
);


-- Matching query:
-- Retrieve trips for vehicle 1
-- between September 1 and September 30, 2026.

SELECT
    trip_id,
    vehicle_id,
    trip_on,
    start_odometer,
    end_odometer

FROM trips

WHERE vehicle_id = 1

AND trip_on >= DATE '2026-09-01'

AND trip_on < DATE '2026-10-01'

ORDER BY trip_on;


-- Display execution plan
EXPLAIN

SELECT
    trip_id,
    vehicle_id,
    trip_on,
    start_odometer,
    end_odometer

FROM trips

WHERE vehicle_id = 1

AND trip_on >= DATE '2026-09-01'

AND trip_on < DATE '2026-10-01'

ORDER BY trip_on;


-- INDEX JUSTIFICATION:
--
-- The index is created on vehicle_id and trip_on.
--
-- vehicle_id is the first column because the query
-- searches for trips belonging to one vehicle.
--
-- trip_on is the second column because the query
-- filters trips within a date range.
--
-- The composite index supports both conditions
-- and helps retrieve matching trips efficiently.



-- ==========================================================
-- QUESTION 8 (G): SCHEDULED JOB [6 MARKS]
--
-- Procedure: pr_refresh_service_alerts()
--
-- Responsibilities:
-- 1. Find all vehicles due for servicing.
-- 2. Insert service alerts for those vehicles.
-- 3. Update existing alerts when kilometres change.
-- 4. Remove alerts when vehicles are no longer due.
--
-- One alert is maintained per vehicle.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts()
LANGUAGE plpgsql
AS $$
BEGIN

    -- Insert alerts for vehicles that have reached
    -- or exceeded the 5,000 kilometre threshold.

    INSERT INTO service_alerts (
        vehicle_id,
        km_since_service,
        flagged_on
    )

    SELECT
        vehicle_id,

        current_odometer - last_service_odometer,

        CURRENT_DATE

    FROM vehicles

    WHERE (
        current_odometer - last_service_odometer
    ) >= 5000


    -- If an alert already exists for the vehicle,
    -- update its kilometres and flagged date.

    ON CONFLICT (vehicle_id)

    DO UPDATE SET

        km_since_service = EXCLUDED.km_since_service,

        flagged_on = EXCLUDED.flagged_on;


    -- Remove alerts for vehicles that are
    -- no longer due for servicing.

    DELETE FROM service_alerts

    WHERE vehicle_id IN (

        SELECT s.vehicle_id

        FROM service_alerts s

        JOIN vehicles v
            ON s.vehicle_id = v.vehicle_id

        WHERE (
            v.current_odometer - v.last_service_odometer
        ) < 5000

    );

END;
$$;



-- ==========================================================
-- QUESTION 8 (G): SCHEDULED JOB USING PG_CRON
--
-- Schedule service alert refresh every Monday
-- at 06:00.
--
-- Cron expression:
-- 0 6 * * 1
--
-- Requires pg_cron installation and configuration.
-- ==========================================================

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule weekly service alert refresh
SELECT cron.schedule(
    'refresh_transport_service_alerts',
    '0 6 * * 1',
    'CALL q8.pr_refresh_service_alerts();'
);


-- Display scheduled jobs
SELECT *
FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 8
-- ==========================================================


-- 1. Display all vehicles
SELECT *
FROM vehicles
ORDER BY vehicle_id;


-- 2. Display all trips
SELECT *
FROM trips
ORDER BY vehicle_id, trip_on;


-- 3. Test the service function for vehicle 1
SELECT fn_service_due(1);


-- 4. Test the service function for vehicle 2
SELECT fn_service_due(2);


-- 5. Test the service function for vehicle 3
SELECT fn_service_due(3);


-- 6. Display vehicles due for servicing
SELECT *
FROM v_service_due
ORDER BY registration;


-- 7. Test the service alert procedure
CALL pr_refresh_service_alerts();


-- 8. Display all service alerts
SELECT *
FROM service_alerts
ORDER BY vehicle_id;


-- 9. Test that the procedure updates existing alerts
-- Run the refresh procedure again.
CALL pr_refresh_service_alerts();


-- 10. Display alerts after refreshing
SELECT *
FROM service_alerts
ORDER BY vehicle_id;


-- 11. Test the trip index query
EXPLAIN

SELECT *
FROM trips

WHERE vehicle_id = 1

AND trip_on >= DATE '2026-09-01'

AND trip_on < DATE '2026-10-01';


-- 12. Display scheduled jobs
SELECT *
FROM cron.job;


-- 13. Display job execution history
SELECT *
FROM cron.job_run_details

WHERE jobid = (
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'refresh_transport_service_alerts'
)

ORDER BY start_time DESC;


-- ==========================================================
-- END OF QUESTION 8
-- ==========================================================
