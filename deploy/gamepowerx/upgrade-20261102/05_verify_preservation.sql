-- Run immediately after 00_preserve_plugin_rows.sql and before any EF migrations.
-- This verifies exact row equality, not only matching counts, and returns no user data.
DO $verify$
BEGIN
    IF EXISTS (SELECT * FROM public."ApplicationUsers" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."ApplicationUsers")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."ApplicationUsers" EXCEPT ALL SELECT * FROM public."ApplicationUsers")
       OR EXISTS (SELECT * FROM public."Classes" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."Classes")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."Classes" EXCEPT ALL SELECT * FROM public."Classes")
       OR EXISTS (SELECT * FROM public."ClassSchoolUser" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."ClassSchoolUser")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."ClassSchoolUser" EXCEPT ALL SELECT * FROM public."ClassSchoolUser")
       OR EXISTS (SELECT * FROM public."ClassTeacher" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."ClassTeacher")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."ClassTeacher" EXCEPT ALL SELECT * FROM public."ClassTeacher")
       OR EXISTS (SELECT * FROM public."Exams" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."Exams")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."Exams" EXCEPT ALL SELECT * FROM public."Exams")
       OR EXISTS (SELECT * FROM public."Grades" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."Grades")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."Grades" EXCEPT ALL SELECT * FROM public."Grades")
       OR EXISTS (SELECT * FROM public."Absences" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."Absences")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."Absences" EXCEPT ALL SELECT * FROM public."Absences")
       OR EXISTS (SELECT * FROM public."AgendaEntries" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."AgendaEntries")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."AgendaEntries" EXCEPT ALL SELECT * FROM public."AgendaEntries")
       OR EXISTS (SELECT * FROM public."StudentDocuments" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."StudentDocuments")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."StudentDocuments" EXCEPT ALL SELECT * FROM public."StudentDocuments")
       OR EXISTS (SELECT * FROM public."NotificationOutbox" EXCEPT ALL SELECT * FROM upgrade_preservation_20261102."NotificationOutbox")
       OR EXISTS (SELECT * FROM upgrade_preservation_20261102."NotificationOutbox" EXCEPT ALL SELECT * FROM public."NotificationOutbox") THEN
        RAISE EXCEPTION 'Preservation archive differs from the restored source tables';
    END IF;
END
$verify$;

SELECT "TableName", "RowCount" FROM upgrade_preservation_20261102."ArchiveManifest" ORDER BY "TableName";
