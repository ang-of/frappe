#!/bin/bash
set -euo pipefail

cd /home/frappe/frappe-bench

: "${SITE_NAME:?SITE_NAME env var is required}"
: "${DB_HOST:?DB_HOST env var is required}"
: "${DB_PASSWORD:?DB_PASSWORD env var is required (fixed, chosen by you)}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD env var is required}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD env var is required}"

DB_PORT="${DB_PORT:-3306}"
DB_ROOT_USER="${DB_ROOT_USER:-root}"
DB_NAME="${DB_NAME:-$(echo -n "$SITE_NAME" | tr -c 'a-zA-Z0-9' '_' | cut -c1-40)}"
REDIS_CACHE="${REDIS_CACHE:-redis://localhost:6379/0}"
REDIS_QUEUE="${REDIS_QUEUE:-redis://localhost:6379/1}"
PORT="${PORT:-8080}"

# sites/ is not persisted between cold starts, so rebuild the assets symlink
# and the site config every time instead of relying on a mounted volume.
rm -rf sites/assets
ln -s /home/frappe/frappe-bench/assets sites/assets

# Bench-level config, not site-level, so it doesn't need a site to exist yet.
# Must run before any `bench migrate`/`new-site` call below — migrate checks
# Redis reachability using whatever's already in common_site_config.json.
bench set-config -g redis_cache "$REDIS_CACHE"
bench set-config -g redis_queue "$REDIS_QUEUE"

db_exists=$(mariadb -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
    -N -B -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${DB_NAME}';")

if [ "$db_exists" = "0" ]; then
    echo "No existing database for ${SITE_NAME} (${DB_NAME}), creating a new site..."
    bench new-site "$SITE_NAME" \
        --db-name "$DB_NAME" \
        --db-password "$DB_PASSWORD" \
        --db-host "$DB_HOST" \
        --db-port "$DB_PORT" \
        --db-root-username "$DB_ROOT_USER" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --install-app lms \
        --set-default
elif [ ! -d "sites/$SITE_NAME" ]; then
    # `bench new-site --no-setup-db` still runs the full install_app("frappe")
    # flow (fixtures, install_basic_docs, ...) even though the schema is
    # already there — reinstalling into an already-installed DB corrupts
    # doctype metadata. Reattaching just needs site_config.json recreated so
    # bench knows which DB to talk to; the schema/data are already correct.
    echo "Database for ${SITE_NAME} (${DB_NAME}) already exists, reattaching site config..."
    mkdir -p "sites/$SITE_NAME"
    cat > "sites/$SITE_NAME/site_config.json" <<-SITECONFIG
	{
	  "db_name": "$DB_NAME",
	  "db_password": "$DB_PASSWORD",
	  "db_host": "$DB_HOST",
	  "db_port": $DB_PORT
	}
	SITECONFIG
    bench use "$SITE_NAME"
    bench --site "$SITE_NAME" migrate
else
    # Site dir and DB both already here (e.g. a container restart that kept
    # its writable layer instead of a fresh one) — nothing to (re)attach.
    echo "Site ${SITE_NAME} already set up, skipping reattach..."
    bench use "$SITE_NAME"
    bench --site "$SITE_NAME" migrate
fi

exec /home/frappe/frappe-bench/env/bin/gunicorn \
    --chdir=/home/frappe/frappe-bench/sites \
    --pythonpath=/home/frappe/frappe-bench \
    --bind="0.0.0.0:${PORT}" \
    --threads="${GUNICORN_THREADS:-4}" \
    --workers="${GUNICORN_WORKERS:-2}" \
    --worker-class=gthread \
    --worker-tmp-dir=/dev/shm \
    --timeout="${GUNICORN_TIMEOUT:-120}" \
    --preload \
    gunicorn_wsgi:application
