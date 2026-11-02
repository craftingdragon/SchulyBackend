# Schuly deployment on server1.gamepowerx.com

The production stack lives at `/root/schuly-deployment` and serves
`https://schuly.gamepowerx.com` through the host nginx proxy. The compose file
bind-mounts PostgreSQL and SeaweedFS data, an ARM64 .NET 10 publish directory,
and a writable plugin store. The Schulware plugin is pinned in `plugins.yml`;
its API URL is set in `plugins-config/Schuly.Plugin.Schulware.yml`.

## November 2026 release

The deployment uses server 3.18.0, Schulware 3.6.0, OdaOrg 1.10.0, and
SchulwareAPI 1.11.0. Backend binaries live in `app-v3.18.0`; plugins and the
manifest use `plugins-v3` and `plugins-v3.yml`. Old binaries and plugin files
remain in their original directories for a complete rollback with the database.
The plugin registry is pinned to fork commit
`751b943ae94ba9c2c89c5878d66993f1caf31d6b`; runtime and API images use digests.

`SsoOnly=true` permits GamepowerX SSO and session refresh/logout, rejecting all
other local `/auth` routes. The new callback registered with Authelia is
`https://schuly.gamepowerx.com/auth/external/gamepowerx/callback`; the app returns
to `schuly://auth/callback`. `LOCAL_LOGIN_SIGNING_KEY` and
`TWO_FACTOR_ENCRYPTION_KEY` are generated once by `prepare-secrets.py` and retained
with the existing encryption keys. SMTP is unnecessary in SSO-only mode.

Use the SQL procedure in `upgrade-20261102` before opening the new service to
traffic. It archives the old rows and imports identities into Toamaisutaa while
preserving application user IDs and provider-account references. The user
authorized the upstream school-data reset. Both provider syncs were successfully
rehearsed on restored data; startup schedules rebuild current school data.

Build the reviewed source with `dotnet publish src/Schuly.API -c Release
-r linux-arm64 --self-contained false -p:Version=3.18.0
-p:InformationalVersion=3.18.0`, and copy the production Angular bundle into
`wwwroot` in the publish directory. Explicit version properties are required
because the upstream tag still contains the previous version in its properties.

Private rollback archives are retained on the deployment workstation under
`deployment/.private-backups/`. Restore the complete database, files, keys,
configuration, and old binaries together; old binaries cannot run against the
upgraded database. Keep the original SchulwareAPI image and its compose file.

Before replacing the `app` directory, ensure `app/plugins` and
`app/plugins-config` exist and `app/plugins.yml` is an empty file. Docker needs
these mountpoints inside the read-only `/app` bind mount. The actual writable
plugin files and manifest live beside `app` and are mounted over those paths.

Production `.env` contains the PostgreSQL and S3 credentials plus persistent
`VAULT_MASTER_KEY`, `DOCUMENTS_ENCRYPTION_KEY`, and `AVATAR_SIGNING_KEY`. Keep
all three keys with the database backup: losing the vault key makes stored
school credentials unreadable, and losing the document key makes newly
encrypted documents unreadable. `prepare-secrets.py` adds keys only when absent
and does not display their values.

## October 2026 migration

The June backend and current upstream backend have incompatible EF migration
baselines. `baseline-bridge.sql` verifies the June migration history and
schema, records the new baseline, adds two catalog columns, and updates the
existing Schulnetz catalog descriptor. It was tested against restored copies
before being applied to production. Do not run it on a different schema without
revalidating its preconditions.

The patched Schulware 2.5.2 plugin copies legacy account secrets into the
new persistent vault before its EF migration drops the old secret columns.
Its migration also preserves auto-refresh for existing accounts. Keep the
backend, plugin, and vault key together when restoring a backup.

Pre-upgrade stopped-state backup on the server:
`/root/schuly-backups/20261016-pre-upgrade/schuly-deployment.tar.gz`.
An off-server copy with the same SHA-256 is held at
`/tmp/schuly-pre-upgrade.tar.gz` on the deployment workstation. The previous
ARM64 binaries and compose file are also in `app.prev-20261016` and
`compose.prev-20261016.yml` on the server.

For rollback, stop the stack, restore the complete pre-upgrade archive
(including PostgreSQL, SeaweedFS, app, config, and `.env`), then start the old
compose file. Restoring only the old binaries against the migrated database is
not supported.
