
/*
============================================================
QUESTION 5: HOSTEL ROOM ALLOCATION
============================================================
*/


-- ==========================================================
-- QUESTION 5 (A): DATABASE AND SEED DATA [6 MARKS]
-- Create the four required tables.
-- Prepare rooms, students and allocations.
-- Demonstrate full, partly occupied and empty rooms.
-- ==========================================================

-- Create a separate schema for Question 5
CREATE SCHEMA IF NOT EXISTS q5;

SET search_path TO q5, public;


-- 1. STUDENTS TABLE
CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    student_number VARCHAR(30) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL
);


-- 2. ROOMS TABLE
CREATE TABLE rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(20) UNIQUE NOT NULL,
    capacity INTEGER NOT NULL CHECK (capacity > 0)
);


-- 3. ALLOCATIONS TABLE
CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_id INTEGER NOT NULL,
    room_id INTEGER NOT NULL,
    allocated_on DATE NOT NULL,
    released_on DATE,
    status VARCHAR(10) NOT NULL,

    FOREIGN KEY (student_id)
    REFERENCES students(student_id),

    FOREIGN KEY (room_id)
    REFERENCES rooms(room_id),

    CHECK (status IN ('ACTIVE', 'ENDED')),

    -- ACTIVE allocations must have no release date.
    -- ENDED allocations must have a release date.
    CHECK (
        (status = 'ACTIVE' AND released_on IS NULL)
        OR
        (status = 'ENDED' AND released_on IS NOT NULL)
    ),

    CHECK (
        released_on IS NULL
        OR released_on >= allocated_on
    )
);


-- 4. OCCUPANCY SNAPSHOT TABLE
CREATE TABLE occupancy_snapshot (
    snapshot_date DATE NOT NULL,
    room_id INTEGER NOT NULL,
    occupied_beds INTEGER NOT NULL,
    free_beds INTEGER NOT NULL,

    PRIMARY KEY (snapshot_date, room_id),

    FOREIGN KEY (room_id)
    REFERENCES rooms(room_id)
);


-- Insert three hostel rooms
INSERT INTO rooms (room_number, capacity)
VALUES
('ROOM-101', 2),
('ROOM-102', 3),
('ROOM-103', 2);


-- Insert six students
INSERT INTO students (student_number, full_name)
VALUES
('MU2024001', 'John Banda'),
('MU2024002', 'Mary Phiri'),
('MU2024003', 'Peter Zulu'),
('MU2024004', 'Grace Tembo'),
('MU2024005', 'James Mwale'),
('MU2024006', 'Sarah Chanda');



-- ==========================================================
-- QUESTION 5 (B): FUNCTION [6 MARKS]
-- Function: fn_free_beds
-- Returns room capacity minus ACTIVE allocation count.
-- Rejects an unknown room.
-- ENDED allocations do not reduce availability.
-- ==========================================================

CREATE OR REPLACE FUNCTION fn_free_beds(
    p_room_id INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INTEGER;
    v_occupied INTEGER;
    v_free_beds INTEGER;
BEGIN

    -- Validate room ID
    IF p_room_id IS NULL THEN
        RAISE EXCEPTION 'Room ID cannot be NULL';
    END IF;

    -- Retrieve room capacity
    SELECT capacity
    INTO v_capacity
    FROM rooms
    WHERE room_id = p_room_id;

    -- Reject unknown room
    IF NOT FOUND THEN
        RAISE EXCEPTION
        'Room ID % does not exist',
        p_room_id;
    END IF;

    -- Count ACTIVE allocations only
    SELECT COUNT(*)::INTEGER
    INTO v_occupied
    FROM allocations
    WHERE room_id = p_room_id
    AND status = 'ACTIVE';

    -- Calculate available beds
    v_free_beds := v_capacity - v_occupied;

    -- Return available beds
    RETURN v_free_beds;

END;
$$;



-- ==========================================================
-- QUESTION 5 (C): PROCEDURE [8 MARKS]
-- Procedure: pr_allocate_room
-- Validates student and room IDs.
-- Ensures the student has no ACTIVE allocation.
-- Checks room availability before allocating.
-- Creates an ACTIVE allocation.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_allocate_room(
    p_student_id INTEGER,
    p_room_id INTEGER,
    p_allocated_on DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_free_beds INTEGER;
BEGIN

    -- Validate student ID
    IF p_student_id IS NULL THEN
        RAISE EXCEPTION 'Student ID cannot be NULL';
    END IF;

    -- Validate room ID
    IF p_room_id IS NULL THEN
        RAISE EXCEPTION 'Room ID cannot be NULL';
    END IF;

    -- Validate allocation date
    IF p_allocated_on IS NULL THEN
        RAISE EXCEPTION 'Allocation date cannot be NULL';
    END IF;

    -- Check whether student exists
    IF NOT EXISTS (
        SELECT 1
        FROM students
        WHERE student_id = p_student_id
    ) THEN
        RAISE EXCEPTION
        'Student ID % does not exist',
        p_student_id;
    END IF;

    -- Check whether room exists
    IF NOT EXISTS (
        SELECT 1
        FROM rooms
        WHERE room_id = p_room_id
    ) THEN
        RAISE EXCEPTION
        'Room ID % does not exist',
        p_room_id;
    END IF;

    -- Check whether student already has an ACTIVE allocation
    IF EXISTS (
        SELECT 1
        FROM allocations
        WHERE student_id = p_student_id
        AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION
        'Student already has an ACTIVE room allocation';
    END IF;

    -- Check available beds
    v_free_beds := fn_free_beds(p_room_id);

    IF v_free_beds <= 0 THEN
        RAISE EXCEPTION
        'Room % is already full',
        p_room_id;
    END IF;

    -- Create new ACTIVE allocation
    -- released_on is NULL because the student is still allocated.
    INSERT INTO allocations (
        student_id,
        room_id,
        allocated_on,
        released_on,
        status
    )
    VALUES (
        p_student_id,
        p_room_id,
        p_allocated_on,
        NULL,
        'ACTIVE'
    );

END;
$$;



-- ==========================================================
-- QUESTION 5 (D): TRIGGER [8 MARKS]
-- Trigger: trg_check_room_capacity
-- BEFORE INSERT OR UPDATE trigger.
-- Enforces room capacity and one ACTIVE allocation
-- per student, including direct SQL changes.
-- Excludes the current row during UPDATE.
-- ==========================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION fn_check_room_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacity INTEGER;
    v_occupied INTEGER;
BEGIN

    -- Perform additional checks only for ACTIVE allocations
    IF NEW.status = 'ACTIVE' THEN

        -- Serialize allocations for the same student.
        -- Prevents simultaneous ACTIVE allocations
        -- for one student in different rooms.
        PERFORM pg_advisory_xact_lock(
            1,
            NEW.student_id
        );

        -- Serialize allocations for the same room.
        -- Prevents simultaneous bookings from exceeding capacity.
        PERFORM pg_advisory_xact_lock(
            2,
            NEW.room_id
        );

        -- Retrieve room capacity and lock the room row
        SELECT capacity
        INTO v_capacity
        FROM rooms
        WHERE room_id = NEW.room_id
        FOR UPDATE;

        -- Check whether room exists
        IF NOT FOUND THEN
            RAISE EXCEPTION
            'Room ID % does not exist',
            NEW.room_id;
        END IF;

        -- Check whether student already has another
        -- ACTIVE allocation.
        IF EXISTS (
            SELECT 1
            FROM allocations
            WHERE student_id = NEW.student_id
            AND status = 'ACTIVE'

            -- Exclude the current allocation during UPDATE
            AND allocation_id IS DISTINCT FROM NEW.allocation_id
        ) THEN

            RAISE EXCEPTION
            'Student % already has another ACTIVE allocation',
            NEW.student_id;

        END IF;

        -- Count other ACTIVE allocations in the room
        SELECT COUNT(*)::INTEGER
        INTO v_occupied
        FROM allocations
        WHERE room_id = NEW.room_id
        AND status = 'ACTIVE'

        -- Exclude the current row during UPDATE
        AND allocation_id IS DISTINCT FROM NEW.allocation_id;

        -- Check room capacity
        IF v_occupied >= v_capacity THEN

            RAISE EXCEPTION
            'Room % is full. Capacity: %, Occupied: %',
            NEW.room_id,
            v_capacity,
            v_occupied;

        END IF;

    END IF;

    RETURN NEW;

END;
$$;


-- Create BEFORE INSERT OR UPDATE trigger
CREATE TRIGGER trg_check_room_capacity
BEFORE INSERT OR UPDATE ON allocations
FOR EACH ROW
EXECUTE FUNCTION fn_check_room_capacity();



-- ==========================================================
-- QUESTION 5 (A): SEED DATA CONTINUED
-- Create sample allocations through the procedure.
-- Demonstrate full, partly occupied and empty rooms.
-- ==========================================================

-- ROOM 101: Capacity 2
-- Allocate two students.
-- Expected: FULL (2 occupied, 0 free).

CALL pr_allocate_room(
    1, 1, CURRENT_DATE
);

CALL pr_allocate_room(
    2, 1, CURRENT_DATE
);


-- ROOM 102: Capacity 3
-- Allocate one student.
-- Expected: PARTLY OCCUPIED (1 occupied, 2 free).

CALL pr_allocate_room(
    3, 2, CURRENT_DATE
);


-- ROOM 103: Capacity 2
-- No ACTIVE allocations.
-- Expected: EMPTY (0 occupied, 2 free).


-- Insert one ENDED allocation for demonstration.
-- An ENDED allocation must not occupy a bed.

INSERT INTO allocations (
    student_id,
    room_id,
    allocated_on,
    released_on,
    status
)
VALUES (
    4,
    3,
    CURRENT_DATE - 30,
    CURRENT_DATE - 5,
    'ENDED'
);



-- ==========================================================
-- QUESTION 5 (E): VIEW [5 MARKS]
-- View: v_room_occupancy
-- Shows every room, its capacity, occupied beds and free beds.
-- Includes rooms with no allocations.
-- ==========================================================

CREATE OR REPLACE VIEW v_room_occupancy AS
SELECT
    r.room_id,
    r.room_number,
    r.capacity,

    COUNT(a.allocation_id)::INTEGER
        AS occupied_beds,

    r.capacity -
    COUNT(a.allocation_id)::INTEGER
        AS free_beds

FROM rooms r

LEFT JOIN allocations a
    ON r.room_id = a.room_id
    AND a.status = 'ACTIVE'

GROUP BY
    r.room_id,
    r.room_number,
    r.capacity;


-- Display room occupancy
SELECT * FROM v_room_occupancy;



-- ==========================================================
-- QUESTION 5 (F): INDEX [5 MARKS]
-- Index: idx_allocations_active_room
-- Supports searching ACTIVE allocations by room_id.
-- ==========================================================

-- Create partial index
CREATE INDEX idx_allocations_active_room
ON allocations (room_id)
WHERE status = 'ACTIVE';


-- Matching query
SELECT *
FROM allocations
WHERE room_id = 1
AND status = 'ACTIVE';


-- Display execution plan
EXPLAIN
SELECT *
FROM allocations
WHERE room_id = 1
AND status = 'ACTIVE';


-- INDEX JUSTIFICATION:
-- room_id is used to search allocations belonging
-- to a particular hostel room.
--
-- The partial index includes only ACTIVE allocations.
--
-- ENDED allocations are excluded because they do not
-- occupy beds.
--
-- This reduces the index size and improves searches
-- for currently occupied rooms.



-- ==========================================================
-- QUESTION 5 (G): SCHEDULED JOB [6 MARKS]
-- Procedure: pr_refresh_occupancy
-- Stores CURRENT_DATE occupancy for every room.
-- Records occupied beds and free beds.
-- Replaces existing values when rerun.
-- ==========================================================

CREATE OR REPLACE PROCEDURE pr_refresh_occupancy()
LANGUAGE plpgsql
AS $$
BEGIN

    -- Calculate occupancy for every room
    -- Include rooms with zero ACTIVE allocations.
    INSERT INTO occupancy_snapshot (
        snapshot_date,
        room_id,
        occupied_beds,
        free_beds
    )
    SELECT
        CURRENT_DATE,
        r.room_id,

        COUNT(a.allocation_id)::INTEGER
            AS occupied_beds,

        r.capacity -
        COUNT(a.allocation_id)::INTEGER
            AS free_beds

    FROM rooms r

    LEFT JOIN allocations a
        ON r.room_id = a.room_id
        AND a.status = 'ACTIVE'

    GROUP BY
        r.room_id,
        r.capacity

    -- Replace the existing snapshot for the same
    -- date and room instead of creating duplicates.
    ON CONFLICT (snapshot_date, room_id)
    DO UPDATE SET
        occupied_beds = EXCLUDED.occupied_beds,
        free_beds = EXCLUDED.free_beds;

END;
$$;


-- Manually test the procedure
CALL pr_refresh_occupancy();


-- Display occupancy snapshot
SELECT * FROM occupancy_snapshot;



-- ==========================================================
-- QUESTION 5 (G): SCHEDULED JOB USING PG_CRON
-- Schedule daily execution at 23:55.
-- Requires pg_cron installation and configuration.
-- ==========================================================

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- Schedule occupancy refresh every day at 23:55
SELECT cron.schedule(
    'refresh_hostel_occupancy',
    '55 23 * * *',
    'CALL q5.pr_refresh_occupancy();'
);


-- Display scheduled jobs
SELECT * FROM cron.job;



-- ==========================================================
-- FINAL TESTING: QUESTION 5
-- ==========================================================

-- 1. Display all students
SELECT * FROM students;


-- 2. Display all rooms
SELECT * FROM rooms;


-- 3. Display all allocations
SELECT * FROM allocations;


-- 4. Display room occupancy
SELECT * FROM v_room_occupancy;


-- 5. Test free beds for Room 101
SELECT fn_free_beds(1);


-- 6. Test free beds for Room 102
SELECT fn_free_beds(2);


-- 7. Test free beds for Room 103
SELECT fn_free_beds(3);


-- 8. Test occupancy refresh procedure
CALL pr_refresh_occupancy();


-- 9. Display occupancy snapshots
SELECT *
FROM occupancy_snapshot
ORDER BY snapshot_date, room_id;


-- 10. Test that ENDED allocations do not occupy beds
SELECT
    room_id,
    COUNT(*) AS active_allocations
FROM allocations
WHERE status = 'ACTIVE'
GROUP BY room_id
ORDER BY room_id;


-- ==========================================================
-- END OF QUESTION 5
-- ==========================================================
