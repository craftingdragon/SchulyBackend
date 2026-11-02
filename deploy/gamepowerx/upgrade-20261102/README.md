# Schuly 1.4.1 to 3.18.0 upgrade data tooling

This directory contains a fail-closed PostgreSQL preservation and identity-import procedure for a restored staging database. It does not deploy software or change production. Target schema assumptions were checked against `/tmp/schulyserver-v3.18.0` and Toamaisutaa 0.14.0 source.

## Order of operations

1. Restore a production backup into an isolated staging database. Keep it isolated from real provider callbacks and disable background synchronization until the upgrade is ready.
2. Run `00_preserve_plugin_rows.sql` on that restored 1.4.1 database before applying EF migrations, then run `05_verify_preservation.sql`. It preserves all `ApplicationUsers`, every table directly deleted by `20261024174204_AddPluginDataSource`, and the class membership join rows removed through cascade. The verifier checks exact row equality. It aborts if the archive schema already exists.
3. Apply the target server's migrations to staging. The target migration clears `NotificationOutbox`, `Grades`, `Absences`, `AgendaEntries`, `StudentDocuments`, `Exams`, and `Classes`, then adds source keys. The user explicitly authorized resetting this school data; the archive remains available for recovery/audit. After migrations, run every enabled provider sync for the linked school account and verify the new rows load correctly.
4. After all migrations create Toamaisutaa tables, run `10_import_gamepowerx_identities.sql` once on staging. It creates a transactional ledger, creates a new Toamaisutaa UUID for each legacy Schuly account, records the opaque old `ExternalId` as the `gamepowerx` subject with issuer `https://auth.gamepowerx.com`, and changes only `ApplicationUsers.ExternalId`; existing `ApplicationUsers.Id` values and all FKs remain untouched. The script does not parse legacy subjects as UUIDs and aborts on mapping conflicts.
5. Run `20_audit.sql`. Require zero identity mismatch, zero unmapped archived account, zero missing archived ApplicationUser IDs, and successful provider resync before enabling auth traffic. Destructive-target counts may be lower than archived counts if providers no longer return older records; this is expected under the authorized school-data reset.
6. Repeat the same sequence against the final production backup during the coordinated cutover. Keep the full database/file/config/key backup and this row archive until the new auth flow and provider data are accepted.

Use `psql --set ON_ERROR_STOP=1 --file <script.sql>` so any raised exception stops the operation. The SQL script uses one transaction per procedure; an error rolls back the ledger/import or preservation schema creation. Do not restore archived rows wholesale after provider resync: the pre-migration schema lacks the external IDs required for safe deduplication.

## Staging validation

- Run preservation against a fresh restored copy; check the `ArchiveManifest` counts against source counts.
- Apply target migrations and verify all seven target tables are empty before resync, then exercise Schoolware and OdaOrg synchronization for each staging-linked account.
- Run identity import twice. The second run must leave counts and mappings unchanged. Verify every user row retains the same `ApplicationUsers.Id`, each `ExternalId` is the mapped auth UUID string, and each old opaque subject appears once under the expected provider and issuer.
- After the first import, run `test_identity_import.sh` with `DATABASE_URL` pointed only at disposable staging. It verifies a later SSO-created account stays outside the archived-user ledger on rerun and a conflicting provider mapping aborts without changing imported identity mappings; it restores the deliberate conflict and removes its test account on exit.
- The importer stores legacy subjects as text without UUID parsing; a non-UUID subject is valid by design.
- Review provider resync results for the linked account. The user authorized the cleared school-data set, so missing historical rows from the source are acceptable.

## Source facts

- `AddPluginDataSource` deletes data before adding `Source`/`ExternalId` columns. Staging archive counts at capture: 1 ApplicationUser, 17 Classes, 17 ClassSchoolUser links, 0 ClassTeacher links, 53 Exams, 53 Grades, 3 Absences, 289 AgendaEntries, 4 StudentDocuments, and 345 NotificationOutbox records.
- The old schema has no provenance columns for the cleared school-data rows. Aggregate inspection cannot reliably label individual rows manual vs provider-synced; the user explicitly authorized the reset.
- `ApplicationUsers.ExternalId` remains the target API lookup key and receives the authenticated `sub`; preserve the row PK and all relations.
- Toamaisutaa stores user/external-login instants as Unix milliseconds. Its unique external-login index is `(ProviderKey, Subject)`.
