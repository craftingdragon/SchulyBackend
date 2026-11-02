-- Run after target migrations have created Toamaisutaa tables and before opening
-- the upgraded service to traffic. The source ExternalId is treated as an opaque
-- OIDC subject; it is not parsed as a UUID.
BEGIN;

LOCK TABLE public."ApplicationUsers" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."ToamaisutaaUsers" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public."ToamaisutaaExternalLogins" IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE upgrade_preservation_20261102."ApplicationUsers" IN SHARE MODE;

CREATE TABLE IF NOT EXISTS public."GamepowerXIdentityImportLedger" (
    "ApplicationUserId" uuid PRIMARY KEY,
    "LegacySubject" text NOT NULL UNIQUE,
    "ToamaisutaaUserId" uuid NOT NULL UNIQUE,
    "ImportedAtUtc" timestamptz NOT NULL DEFAULT clock_timestamp()
);

DO $validate$
BEGIN
    IF to_regclass('public."ApplicationUsers"') IS NULL
       OR to_regclass('public."ToamaisutaaUsers"') IS NULL
       OR to_regclass('public."ToamaisutaaExternalLogins"') IS NULL
       OR to_regclass('upgrade_preservation_20261102."ApplicationUsers"') IS NULL THEN
        RAISE EXCEPTION 'Required archived source or Toamaisutaa tables are missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM upgrade_preservation_20261102."ApplicationUsers"
        WHERE "ExternalId" IS NULL OR btrim("ExternalId") = '' OR length("ExternalId") > 256
    ) THEN
        RAISE EXCEPTION 'Archived ApplicationUsers contains a missing/blank/overlength legacy subject';
    END IF;

    IF EXISTS (
        SELECT 1 FROM upgrade_preservation_20261102."ApplicationUsers" old
        LEFT JOIN public."ApplicationUsers" current ON current."Id" = old."Id"
        WHERE current."Id" IS NULL
    ) THEN
        RAISE EXCEPTION 'An archived ApplicationUser row is missing after migrations';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public."GamepowerXIdentityImportLedger" l
        LEFT JOIN upgrade_preservation_20261102."ApplicationUsers" old
          ON old."Id" = l."ApplicationUserId" AND old."ExternalId" = l."LegacySubject"
        LEFT JOIN public."ApplicationUsers" current ON current."Id" = l."ApplicationUserId"
        WHERE old."Id" IS NULL OR current."Id" IS NULL
           OR (current."ExternalId" <> l."LegacySubject" AND current."ExternalId" <> l."ToamaisutaaUserId"::text)
    ) THEN
        RAISE EXCEPTION 'Existing identity ledger conflicts with ApplicationUsers; stop for manual review';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM upgrade_preservation_20261102."ApplicationUsers" a
        JOIN public."ToamaisutaaExternalLogins" e
          ON e."ProviderKey" = 'gamepowerx' AND e."Subject" = a."ExternalId"
        LEFT JOIN public."GamepowerXIdentityImportLedger" l
          ON l."ApplicationUserId" = a."Id" AND l."LegacySubject" = a."ExternalId"
        WHERE l."ApplicationUserId" IS NULL
    ) THEN
        RAISE EXCEPTION 'A legacy subject is already linked by Toamaisutaa outside this ledger';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public."GamepowerXIdentityImportLedger" l
        LEFT JOIN public."ToamaisutaaUsers" u ON u."Id" = l."ToamaisutaaUserId"
        LEFT JOIN public."ToamaisutaaExternalLogins" e
          ON e."ProviderKey" = 'gamepowerx' AND e."Subject" = l."LegacySubject"
         AND e."UserId" = l."ToamaisutaaUserId" AND e."Issuer" = 'https://auth.gamepowerx.com'
        WHERE u."Id" IS NULL OR e."Id" IS NULL
    ) THEN
        RAISE EXCEPTION 'An existing ledger mapping is incomplete or conflicting';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."GamepowerXIdentityImportLedger" l
        JOIN upgrade_preservation_20261102."ApplicationUsers" a ON a."Id" = l."ApplicationUserId"
        JOIN public."ToamaisutaaUsers" u ON u."Id" = l."ToamaisutaaUserId"
        JOIN public."ApplicationUsers" current ON current."Id" = a."Id"
        WHERE current."ExternalId" = l."LegacySubject"
    ) THEN
        RAISE EXCEPTION 'An assigned Toamaisutaa UUID is already occupied by an unmigrated identity';
    END IF;
END
$validate$;

-- A previous successful run is represented by the ledger. Unmapped legacy users
-- receive fresh UUIDs, recorded in the ledger in this same transaction.
INSERT INTO public."GamepowerXIdentityImportLedger" ("ApplicationUserId", "LegacySubject", "ToamaisutaaUserId")
SELECT a."Id", a."ExternalId", gen_random_uuid()
FROM upgrade_preservation_20261102."ApplicationUsers" a
LEFT JOIN public."GamepowerXIdentityImportLedger" l ON l."ApplicationUserId" = a."Id"
WHERE l."ApplicationUserId" IS NULL;

-- The ledger is the only authority for the UUID assigned to an old Schuly account.
INSERT INTO public."ToamaisutaaUsers"
    ("Id", "UserName", "Email", "DisplayName", "PictureUrl", "SecurityStamp", "CreatedAt", "UpdatedAt")
SELECT l."ToamaisutaaUserId", NULL, a."Email", a."DisplayName", a."ProfilePictureUrl",
       gen_random_uuid()::text,
       (extract(epoch FROM a."CreatedAt") * 1000)::bigint,
       (extract(epoch FROM a."UpdatedAt") * 1000)::bigint
FROM public."GamepowerXIdentityImportLedger" l
JOIN upgrade_preservation_20261102."ApplicationUsers" a ON a."Id" = l."ApplicationUserId"
JOIN public."ApplicationUsers" current ON current."Id" = l."ApplicationUserId"
WHERE current."ExternalId" = l."LegacySubject";

INSERT INTO public."ToamaisutaaExternalLogins"
    ("Id", "UserId", "ProviderKey", "Subject", "Issuer", "CreatedAt", "LastSignInAt")
SELECT gen_random_uuid(), l."ToamaisutaaUserId", 'gamepowerx', l."LegacySubject",
       'https://auth.gamepowerx.com', (extract(epoch FROM clock_timestamp()) * 1000)::bigint, NULL
FROM public."GamepowerXIdentityImportLedger" l
JOIN upgrade_preservation_20261102."ApplicationUsers" a ON a."Id" = l."ApplicationUserId"
JOIN public."ApplicationUsers" current ON current."Id" = l."ApplicationUserId"
WHERE current."ExternalId" = l."LegacySubject";

-- Detect a UUID collision or wrong pre-existing row before changing app lookup keys.
DO $verify$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public."GamepowerXIdentityImportLedger" l
        JOIN public."ApplicationUsers" a ON a."Id" = l."ApplicationUserId"
        LEFT JOIN public."ToamaisutaaUsers" u ON u."Id" = l."ToamaisutaaUserId"
        LEFT JOIN public."ToamaisutaaExternalLogins" e
          ON e."ProviderKey" = 'gamepowerx' AND e."Subject" = l."LegacySubject"
        WHERE a."ExternalId" = l."LegacySubject"
          AND (u."Id" IS NULL OR e."Id" IS NULL OR e."UserId" <> l."ToamaisutaaUserId"
               OR e."Issuer" IS DISTINCT FROM 'https://auth.gamepowerx.com')
    ) THEN
        RAISE EXCEPTION 'Imported auth rows do not match the ledger; transaction rolled back';
    END IF;
END
$verify$;

UPDATE public."ApplicationUsers" a
SET "ExternalId" = l."ToamaisutaaUserId"::text
FROM public."GamepowerXIdentityImportLedger" l
WHERE a."Id" = l."ApplicationUserId" AND a."ExternalId" = l."LegacySubject";

-- Assert stable primary keys and all imported mappings before commit.
DO $final_check$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public."GamepowerXIdentityImportLedger" l
        LEFT JOIN public."ApplicationUsers" a ON a."Id" = l."ApplicationUserId"
        LEFT JOIN public."ToamaisutaaUsers" u ON u."Id" = l."ToamaisutaaUserId"
        LEFT JOIN public."ToamaisutaaExternalLogins" e
          ON e."ProviderKey" = 'gamepowerx' AND e."Subject" = l."LegacySubject"
         AND e."UserId" = l."ToamaisutaaUserId" AND e."Issuer" = 'https://auth.gamepowerx.com'
        WHERE a."Id" IS NULL OR a."ExternalId" <> l."ToamaisutaaUserId"::text
           OR u."Id" IS NULL OR e."Id" IS NULL
    ) THEN
        RAISE EXCEPTION 'Final identity import validation failed; transaction rolled back';
    END IF;
END
$final_check$;

COMMIT;
