#!/bin/bash
# aralert-update.sh: Back up ARALert, verify archive, apply update, and check health
# Authors: L. Omadto, N.J. Alcovindas, J.B. Licup (BSIT)
# Usage: sudo scripts/aralert-update.sh <UPDATE_DIR | --simulate-broken>
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONF_FILE="/etc/aralert/aralert.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo scripts/aralert-update.sh <UPDATE_DIR | --simulate-broken>"
    echo "Options:"
    echo "  UPDATE_DIR         Folder containing updated ARALert files"
    echo "  --simulate-broken  Inject a broken update to test failure and manual restore"
    echo "  --help             Show this help message"
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Error: Provide an UPDATE_DIR or --simulate-broken. Run with --help for usage."
    exit 2
fi

USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: $CONF_FILE not found. Run aralert-install.sh first."
    exit 1
fi

PERM=`stat -c "%a" "$CONF_FILE"`
if [ "$PERM" != "600" ]; then
    echo "Error: $CONF_FILE must have 600 permissions."
    exit 1
fi

. "$CONF_FILE"

if [ "$1" != "--simulate-broken" ] && [ ! -d "$1" ]; then
    echo "Error: Update directory $1 does not exist."
    exit 1
fi

# 1. Back up PostgreSQL database and application files
STAMP=`date +%Y%m%d-%H%M%S`
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

ARCHIVE_FILE="$BACKUP_DIR/aralert-pre-update-$STAMP.tar.gz"
SQL_FILE="$BACKUP_DIR/aralert-db-$STAMP.sql"

echo "[1/4] Backing up database and application files..."
PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > "$SQL_FILE"
if [ $? -ne 0 ]; then
    echo "Error: Database backup failed."
    exit 1
fi

tar -czf "$ARCHIVE_FILE" --exclude='backend/venv' --exclude='frontend/node_modules' -C "$APP_DIR" .
if [ $? -ne 0 ]; then
    echo "Error: Archive creation failed."
    exit 1
fi
chmod 600 "$ARCHIVE_FILE" "$SQL_FILE"

# 2. Check that the backup archive and SQL dump are intact
echo "[2/4] Verifying backup archive ($ARCHIVE_FILE)..."
tar -tzf "$ARCHIVE_FILE" >/dev/null 2>&1 && [ -s "$SQL_FILE" ]
if [ $? -ne 0 ]; then
    echo "Error: Backup verification failed."
    exit 1
fi
echo "Backup verified: $ARCHIVE_FILE"

# 3. Apply the update
echo "[3/4] Applying update..."
if [ "$1" = "--simulate-broken" ]; then
    echo "" >> "$APP_DIR/backend/api/urls.py"
    echo "raise RuntimeError('Broken update demo')" >> "$APP_DIR/backend/api/urls.py"
else
    rsync -a --exclude='.git' --exclude='backend/venv' --exclude='backend/.env' "$1/" "$APP_DIR/"
fi
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
chmod 600 "$APP_DIR/backend/.env"

# 4. Restart service and verify /api/health/ responds
echo "[4/4] Restarting $APP_NAME and checking health..."
systemctl restart aralert
TRIES=0
HEALTH_OK=0
while [ $TRIES -lt 4 ]; do
    sleep 2
    if curl -s --max-time 3 "$HEALTH_URL" | grep -q "healthy"; then
        HEALTH_OK=1
        break
    fi
    TRIES=$(( $TRIES + 1 ))
done

if [ $HEALTH_OK -eq 1 ]; then
    echo "SUCCESS: Update applied and verified ($HEALTH_URL)."
    echo "Backup saved at: $ARCHIVE_FILE"
    exit 0
else
    systemctl stop aralert
    echo "FAILURE: Application check failed after update!"
    echo "To restore the backup by hand, run this exact command:"
    echo ""
    echo "  sudo tar -xzf $ARCHIVE_FILE -C $APP_DIR && sudo chown -R $APP_USER:$APP_GROUP $APP_DIR && sudo systemctl restart aralert"
    echo ""
    exit 1
fi
