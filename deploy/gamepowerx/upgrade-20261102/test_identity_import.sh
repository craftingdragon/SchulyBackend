#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to a disposable migrated staging database}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_user_id="$(cat /proc/sys/kernel/random/uuid)"
test_login_id="$(cat /proc/sys/kernel/random/uuid)"
test_subject="post-upgrade-test-${test_user_id}"
cleanup() {
    psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 -v id="$test_user_id" <<'SQL' >/dev/null
UPDATE public."ToamaisutaaExternalLogins" e
SET "Issuer" = 'https://auth.gamepowerx.com'
WHERE e."Issuer" = 'https://conflict.invalid'
  AND EXISTS (SELECT 1 FROM public."GamepowerXIdentityImportLedger" l
              WHERE l."ToamaisutaaUserId" = e."UserId" AND l."LegacySubject" = e."Subject");
DELETE FROM public."ApplicationUsers" WHERE "Id" = :'id'::uuid;
DELETE FROM public."ToamaisutaaUsers" WHERE "Id" = :'id'::uuid;
SQL
}
trap cleanup EXIT

run_import() {
    psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$script_dir/10_import_gamepowerx_identities.sql" >/dev/null
}

run_import
baseline_ledger="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM public."GamepowerXIdentityImportLedger"')"

# Simulate a legitimate post-upgrade SSO account, which must not be mistaken for
# one of the original identities on a later import run.
psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 -v id="$test_user_id" -v login_id="$test_login_id" -v subject="$test_subject" <<'SQL' >/dev/null
BEGIN;
INSERT INTO public."ToamaisutaaUsers"
    ("Id", "UserName", "Email", "DisplayName", "PictureUrl", "SecurityStamp", "CreatedAt", "UpdatedAt")
VALUES (:'id'::uuid, NULL, 'migration-test@invalid.example', 'Migration test', NULL,
        gen_random_uuid()::text, (extract(epoch FROM clock_timestamp()) * 1000)::bigint,
        (extract(epoch FROM clock_timestamp()) * 1000)::bigint);
INSERT INTO public."ToamaisutaaExternalLogins"
    ("Id", "UserId", "ProviderKey", "Subject", "Issuer", "CreatedAt", "LastSignInAt")
VALUES (:'login_id'::uuid, :'id'::uuid, 'gamepowerx', :'subject', 'https://auth.gamepowerx.com',
        (extract(epoch FROM clock_timestamp()) * 1000)::bigint, NULL);
INSERT INTO public."ApplicationUsers" ("Id", "ExternalId", "Email", "DisplayName", "CreatedAt", "UpdatedAt")
VALUES (:'id'::uuid, :'id', 'migration-test@invalid.example', 'Migration test', now(), now());
COMMIT;
SQL

run_import
new_user_ledger_rows="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.\"GamepowerXIdentityImportLedger\" WHERE \"ApplicationUserId\" = '${test_user_id}'::uuid")"
ledger_after_rerun="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM public."GamepowerXIdentityImportLedger"')"
new_user_external_id="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c "SELECT \"ExternalId\" FROM public.\"ApplicationUsers\" WHERE \"Id\" = '${test_user_id}'::uuid")"
if [[ "$new_user_ledger_rows" != 0 || "$ledger_after_rerun" != "$baseline_ledger" || "$new_user_external_id" != "$test_user_id" ]]; then
    echo 'Rerun imported or modified a post-upgrade SSO account' >&2
    exit 1
fi

# Corrupt one already-imported link, expect fail-closed behavior, then restore it.
psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
UPDATE public."ToamaisutaaExternalLogins" e
SET "Issuer" = 'https://conflict.invalid'
WHERE e."ProviderKey" = 'gamepowerx'
  AND e."Issuer" = 'https://auth.gamepowerx.com'
  AND EXISTS (SELECT 1 FROM public."GamepowerXIdentityImportLedger" l
              WHERE l."ToamaisutaaUserId" = e."UserId" AND l."LegacySubject" = e."Subject");
SQL
conflicting_links="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.\"ToamaisutaaExternalLogins\" WHERE \"Issuer\" = 'https://conflict.invalid'")"
if [[ "$conflicting_links" == 0 ]]; then
    echo 'No imported mapping was available for the conflict check' >&2
    exit 1
fi

if psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$script_dir/10_import_gamepowerx_identities.sql" >/dev/null 2>&1; then
    echo 'Expected identity import to abort on the corrupted mapping' >&2
    exit 1
fi

ledger_after_conflict="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM public."GamepowerXIdentityImportLedger"')"
identity_mismatches="$(psql -X "$DATABASE_URL" -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM public."GamepowerXIdentityImportLedger" l JOIN public."ApplicationUsers" a ON a."Id" = l."ApplicationUserId" WHERE a."ExternalId" <> l."ToamaisutaaUserId"::text')"
if [[ "$ledger_after_conflict" != "$baseline_ledger" || "$identity_mismatches" != 0 ]]; then
    echo 'Conflicting rerun changed the import ledger or app identity' >&2
    exit 1
fi
psql -X "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
UPDATE public."ToamaisutaaExternalLogins" e
SET "Issuer" = 'https://auth.gamepowerx.com'
WHERE e."Issuer" = 'https://conflict.invalid'
  AND EXISTS (SELECT 1 FROM public."GamepowerXIdentityImportLedger" l
              WHERE l."ToamaisutaaUserId" = e."UserId" AND l."LegacySubject" = e."Subject");
SQL

echo 'Identity import rerun and conflict checks passed.'
