-- Schuly old-chain to 20260622211015_InitialCreate bridge.
-- Run only after a verified backup and before the target backend migration.
-- The target InitialCreate is a full-schema baseline; the legacy schema already
-- contains these objects, so record the baseline without executing its Up().
BEGIN;
DO $bridge$
DECLARE
    expected_old_ids text[] := ARRAY[
        '20260427151804_Init',
        '20260527200228_AgendaEntryFlexibleScope',
        '20260527201303_DropSchoolUserStudentNumberTeacherCode',
        '20260527202455_ReadPathIndexes',
        '20260527203051_MoreScopeIndexes',
        '20260527204101_SchemaHardening',
        '20260527204909_ScopedEmailUniqueAndAuthFix',
        '20260527205139_ScopedClassNameUnique',
        '20260527205746_StudentDocumentsAndSemesterReports',
        '20260527210307_TeachersAndClassDetails',
        '20260527211051_ExamGradeDetailFields',
        '20260527211322_DropExamGroup',
        '20260527211518_AgendaEntryEndDateAndHolidayType',
        '20260529062550_AddSchoolLogoAndUserProfilePicture',
        '20260614084526_LinkTeacherToApplicationUser',
        '20260614133639_SchemaCleanupDropDeadColumns',
        '20260615054320_AddSchoolSystems',
        '20260615194411_AddSchoolSystemStatelessBasePath'
    ];
    missing_ids text[];
    missing_tables text[];
    user_count bigint;
    school_count bigint;
    school_user_count bigint;
BEGIN
    IF to_regclass('public."__EFMigrationsHistory"') IS NULL THEN
        RAISE EXCEPTION 'Missing public.__EFMigrationsHistory; refusing Schuly baseline bridge';
    END IF;

    IF to_regclass('public."SchoolSystems"') IS NULL THEN
        RAISE EXCEPTION 'Missing public.SchoolSystems; refusing catalog bridge';
    END IF;
    IF (SELECT count(*) FROM public."SchoolSystems" WHERE "Key" = 'schulnetz') <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one existing schulnetz catalog row';
    END IF;

    IF EXISTS (SELECT 1 FROM public."__EFMigrationsHistory" WHERE "MigrationId" = '20260622211015_InitialCreate') THEN
        RAISE NOTICE 'Target baseline already recorded; bridge is a no-op';
        RETURN;
    END IF;

    SELECT array_agg(x.id ORDER BY x.id) INTO missing_ids
    FROM unnest(expected_old_ids) AS x(id)
    WHERE NOT EXISTS (
        SELECT 1 FROM public."__EFMigrationsHistory" h WHERE h."MigrationId" = x.id
    );
    IF missing_ids IS NOT NULL THEN
        RAISE EXCEPTION 'Unexpected EF history; missing expected old IDs: %', missing_ids;
    END IF;

    IF (SELECT count(*) FROM public."__EFMigrationsHistory") <> cardinality(expected_old_ids) THEN
        RAISE EXCEPTION 'Unexpected EF history row count; expected %, found %',
            cardinality(expected_old_ids), (SELECT count(*) FROM public."__EFMigrationsHistory");
    END IF;

    IF EXISTS (
        SELECT 1 FROM public."__EFMigrationsHistory"
        WHERE "MigrationId" IN (
            '20260719113929_ScopeSchoolUserUniqueToApplicationUser',
            '20260909111745_AddVaultEntries',
            '20260909154119_AddNotifications',
            '20260909162139_AddTickerQ',
            '20260909184341_AddAccountRetention'
        )
    ) THEN
        RAISE EXCEPTION 'Target migration history is partially applied; refusing baseline bridge';
    END IF;

    SELECT array_agg(t.name ORDER BY t.name) INTO missing_tables
    FROM unnest(ARRAY[
        'Absences', 'AgendaEntries', 'ClassSchoolUser', 'ClassTeacher', 'Classes',
        'Exams', 'Grades', 'SchoolSystems', 'SchoolUsers', 'Schools',
        'SemesterReports', 'SemesterSubjectGrades', 'StudentDocuments',
        'Teachers', 'ApplicationUsers'
    ]) AS t(name)
    WHERE to_regclass(format('public.%I', t.name)) IS NULL;
    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION 'Legacy schema is incomplete; missing tables: %', missing_tables;
    END IF;

    IF to_regclass('public."VaultEntries"') IS NOT NULL THEN
        RAISE EXCEPTION 'VaultEntries exists without the target migration marker; inspect partial migration state';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'IX_SchoolUsers_SchoolId_Email'
    ) THEN
        RAISE EXCEPTION 'Expected legacy SchoolUsers index is missing';
    END IF;

    SELECT count(*) INTO user_count FROM public."ApplicationUsers";
    SELECT count(*) INTO school_count FROM public."Schools";
    SELECT count(*) INTO school_user_count FROM public."SchoolUsers";
    IF user_count <> 1 OR school_count <> 1 OR school_user_count <> 1 THEN
        RAISE EXCEPTION 'Dataset differs from verified backup: ApplicationUsers=%, Schools=%, SchoolUsers=%',
            user_count, school_count, school_user_count;
    END IF;

    INSERT INTO public."__EFMigrationsHistory" ("MigrationId", "ProductVersion")
    VALUES ('20260622211015_InitialCreate', '10.0.7');
    RAISE NOTICE 'Recorded existing schema as target baseline 20260622211015_InitialCreate';
END
$bridge$;

-- The June local chain has SchoolSystems rows with a different shape. The new
-- seeder is insert-only, so restore the nullable target columns and update the
-- existing Schulnetz descriptor in place while preserving its ID and flags.
ALTER TABLE public."SchoolSystems"
    ADD COLUMN IF NOT EXISTS "PluginBasePath" text,
    ADD COLUMN IF NOT EXISTS "PrivateAuthStrategy" character varying(50);

UPDATE public."SchoolSystems"
SET "DisplayName" = 'Schulnetz',
    "LoginMethod" = 'credentials',
    "PrivateAuthStrategy" = 'token',
    "StatelessBasePath" = '/api/plugins/schulware/stateless',
    "PluginBasePath" = '/api/plugins/schulware',
    "LoginFields" = '[
      {"Key":"baseUrl","Label":"Schulnetz URL","Type":"url","Placeholder":"https://your-schulnetz.example.ch","DefaultValue":null,"Required":true},
      {"Key":"email","Label":"Email","Type":"text","Placeholder":null,"DefaultValue":null,"Required":true},
      {"Key":"password","Label":"Password","Type":"password","Placeholder":null,"DefaultValue":null,"Required":true},
      {"Key":"totp","Label":"2FA secret (optional)","Type":"totp","Placeholder":"TOTP secret or otpauth:// URI","DefaultValue":null,"Required":false}
    ]'::jsonb
WHERE "Key" = 'schulnetz';
COMMIT;
