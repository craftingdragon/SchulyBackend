-- Read-only post-migration checks. Every reported count must be reviewed before
-- production traffic is enabled; secrets and user values are deliberately omitted.
SELECT 'application_users' AS check_name,
       (SELECT count(*) FROM public."ApplicationUsers") AS application_users,
       (SELECT count(*) FROM public."GamepowerXIdentityImportLedger") AS ledger_rows,
       (SELECT count(*) FROM public."ToamaisutaaUsers") AS auth_users,
       (SELECT count(*) FROM public."ToamaisutaaExternalLogins"
         WHERE "ProviderKey" = 'gamepowerx' AND "Issuer" = 'https://auth.gamepowerx.com') AS gamepowerx_logins;

SELECT 'identity_mismatches' AS check_name, count(*) AS failures
FROM public."GamepowerXIdentityImportLedger" l
LEFT JOIN public."ApplicationUsers" a ON a."Id" = l."ApplicationUserId"
LEFT JOIN public."ToamaisutaaUsers" u ON u."Id" = l."ToamaisutaaUserId"
LEFT JOIN public."ToamaisutaaExternalLogins" e
  ON e."ProviderKey" = 'gamepowerx' AND e."Subject" = l."LegacySubject"
 AND e."UserId" = l."ToamaisutaaUserId" AND e."Issuer" = 'https://auth.gamepowerx.com'
WHERE a."Id" IS NULL OR a."ExternalId" <> l."ToamaisutaaUserId"::text
   OR u."Id" IS NULL OR e."Id" IS NULL;

SELECT 'legacy_users_without_mapping' AS check_name, count(*) AS failures
FROM upgrade_preservation_20261102."ApplicationUsers" a
LEFT JOIN public."GamepowerXIdentityImportLedger" l ON l."ApplicationUserId" = a."Id"
WHERE l."ApplicationUserId" IS NULL;

SELECT m."TableName", m."RowCount" AS archived_rows,
       CASE m."TableName"
         WHEN 'Classes' THEN (SELECT count(*) FROM public."Classes")
         WHEN 'Exams' THEN (SELECT count(*) FROM public."Exams")
         WHEN 'Grades' THEN (SELECT count(*) FROM public."Grades")
         WHEN 'Absences' THEN (SELECT count(*) FROM public."Absences")
         WHEN 'AgendaEntries' THEN (SELECT count(*) FROM public."AgendaEntries")
         WHEN 'StudentDocuments' THEN (SELECT count(*) FROM public."StudentDocuments")
         WHEN 'NotificationOutbox' THEN (SELECT count(*) FROM public."NotificationOutbox")
         WHEN 'ApplicationUsers' THEN (SELECT count(*) FROM public."ApplicationUsers")
         WHEN 'ClassSchoolUser' THEN (SELECT count(*) FROM public."ClassSchoolUser")
         WHEN 'ClassTeacher' THEN (SELECT count(*) FROM public."ClassTeacher")
       END AS current_rows
FROM upgrade_preservation_20261102."ArchiveManifest" m
ORDER BY m."TableName";

-- ApplicationUser PK / relationship IDs must remain intact through migration.
SELECT 'application_user_ids_missing_from_archive' AS check_name, count(*) AS failures
FROM upgrade_preservation_20261102."ApplicationUsers" old
LEFT JOIN public."ApplicationUsers" current ON current."Id" = old."Id"
WHERE current."Id" IS NULL;

-- Report legacy rows without exposing their content. Old AddPluginDataSource
-- cannot map these records to provider IDs; resync is the safe reconstruction path.
SELECT 'archived_rows' AS check_name, "TableName", "RowCount"
FROM upgrade_preservation_20261102."ArchiveManifest"
WHERE "TableName" <> 'ApplicationUsers'
ORDER BY "TableName";
