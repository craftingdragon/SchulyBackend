-- Run on a restored staging copy before applying migrations. This is intentionally
-- fail-closed: a previous archive schema is never overwritten.
BEGIN;

LOCK TABLE public."ApplicationUsers", public."Classes", public."ClassSchoolUser", public."ClassTeacher",
           public."Exams", public."Grades",
           public."Absences", public."AgendaEntries", public."StudentDocuments",
           public."NotificationOutbox" IN SHARE MODE;

DO $preflight$
BEGIN
    IF to_regclass('public."ApplicationUsers"') IS NULL THEN
        RAISE EXCEPTION 'Expected public.ApplicationUsers; wrong database/schema';
    END IF;
    IF to_regclass('public."Classes"') IS NULL
       OR to_regclass('public."ClassSchoolUser"') IS NULL
       OR to_regclass('public."ClassTeacher"') IS NULL
       OR to_regclass('public."Exams"') IS NULL
       OR to_regclass('public."Grades"') IS NULL
       OR to_regclass('public."Absences"') IS NULL
       OR to_regclass('public."AgendaEntries"') IS NULL
       OR to_regclass('public."StudentDocuments"') IS NULL
       OR to_regclass('public."NotificationOutbox"') IS NULL THEN
        RAISE EXCEPTION 'One or more AddPluginDataSource target tables are missing';
    END IF;
    IF to_regnamespace('upgrade_preservation_20261102') IS NOT NULL THEN
        RAISE EXCEPTION 'upgrade_preservation_20261102 already exists; inspect it before proceeding';
    END IF;
END
$preflight$;

CREATE SCHEMA upgrade_preservation_20261102;

CREATE TABLE upgrade_preservation_20261102."ApplicationUsers" AS TABLE public."ApplicationUsers";
CREATE TABLE upgrade_preservation_20261102."Classes" AS TABLE public."Classes";
CREATE TABLE upgrade_preservation_20261102."ClassSchoolUser" AS TABLE public."ClassSchoolUser";
CREATE TABLE upgrade_preservation_20261102."ClassTeacher" AS TABLE public."ClassTeacher";
CREATE TABLE upgrade_preservation_20261102."Exams" AS TABLE public."Exams";
CREATE TABLE upgrade_preservation_20261102."Grades" AS TABLE public."Grades";
CREATE TABLE upgrade_preservation_20261102."Absences" AS TABLE public."Absences";
CREATE TABLE upgrade_preservation_20261102."AgendaEntries" AS TABLE public."AgendaEntries";
CREATE TABLE upgrade_preservation_20261102."StudentDocuments" AS TABLE public."StudentDocuments";
CREATE TABLE upgrade_preservation_20261102."NotificationOutbox" AS TABLE public."NotificationOutbox";

CREATE TABLE upgrade_preservation_20261102."ArchiveManifest" (
    "CapturedAtUtc" timestamptz NOT NULL,
    "TableName" text NOT NULL PRIMARY KEY,
    "RowCount" bigint NOT NULL
);

INSERT INTO upgrade_preservation_20261102."ArchiveManifest" VALUES
    (clock_timestamp(), 'ApplicationUsers', (SELECT count(*) FROM public."ApplicationUsers")),
    (clock_timestamp(), 'Classes', (SELECT count(*) FROM public."Classes")),
    (clock_timestamp(), 'ClassSchoolUser', (SELECT count(*) FROM public."ClassSchoolUser")),
    (clock_timestamp(), 'ClassTeacher', (SELECT count(*) FROM public."ClassTeacher")),
    (clock_timestamp(), 'Exams', (SELECT count(*) FROM public."Exams")),
    (clock_timestamp(), 'Grades', (SELECT count(*) FROM public."Grades")),
    (clock_timestamp(), 'Absences', (SELECT count(*) FROM public."Absences")),
    (clock_timestamp(), 'AgendaEntries', (SELECT count(*) FROM public."AgendaEntries")),
    (clock_timestamp(), 'StudentDocuments', (SELECT count(*) FROM public."StudentDocuments")),
    (clock_timestamp(), 'NotificationOutbox', (SELECT count(*) FROM public."NotificationOutbox"));

-- Verify copies match at capture time. The full database backup remains the rollback
-- artifact; these row copies specifically protect the destructive migration's targets.
DO $verify$
BEGIN
    IF (SELECT count(*) FROM public."ApplicationUsers") <> (SELECT count(*) FROM upgrade_preservation_20261102."ApplicationUsers")
       OR (SELECT count(*) FROM public."Classes") <> (SELECT count(*) FROM upgrade_preservation_20261102."Classes")
       OR (SELECT count(*) FROM public."ClassSchoolUser") <> (SELECT count(*) FROM upgrade_preservation_20261102."ClassSchoolUser")
       OR (SELECT count(*) FROM public."ClassTeacher") <> (SELECT count(*) FROM upgrade_preservation_20261102."ClassTeacher")
       OR (SELECT count(*) FROM public."Exams") <> (SELECT count(*) FROM upgrade_preservation_20261102."Exams")
       OR (SELECT count(*) FROM public."Grades") <> (SELECT count(*) FROM upgrade_preservation_20261102."Grades")
       OR (SELECT count(*) FROM public."Absences") <> (SELECT count(*) FROM upgrade_preservation_20261102."Absences")
       OR (SELECT count(*) FROM public."AgendaEntries") <> (SELECT count(*) FROM upgrade_preservation_20261102."AgendaEntries")
       OR (SELECT count(*) FROM public."StudentDocuments") <> (SELECT count(*) FROM upgrade_preservation_20261102."StudentDocuments")
       OR (SELECT count(*) FROM public."NotificationOutbox") <> (SELECT count(*) FROM upgrade_preservation_20261102."NotificationOutbox") THEN
        RAISE EXCEPTION 'Archived row counts differ from source';
    END IF;
END
$verify$;

COMMIT;
