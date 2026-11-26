#!/bin/bash
# aralert-install.sh: Install and configure ARALert on Ubuntu / WSL
# Authors: L. Omadto, N.J. Alcovindas, J.B. Licup (BSIT)
# Usage: sudo scripts/aralert-install.sh [SOURCE_DIR]
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONF_FILE="/etc/aralert/aralert.conf"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo scripts/aralert-install.sh [SOURCE_DIR]"
    echo "Options:"
    echo "  --help    Show this help message"
    exit 0
fi

if [ $# -ge 1 ]; then
    SOURCE_DIR="$1"
fi

USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

if [ ! -f "$SOURCE_DIR/backend/manage.py" ]; then
    if [ -f "../backend/manage.py" ]; then
        SOURCE_DIR=".."
    else
        echo "Error: ARALert source folder not found in $SOURCE_DIR."
        exit 1
    fi
fi

# Create config file with chmod 600 (no hardcoded passwords)
if [ ! -f "$CONF_FILE" ]; then
    mkdir -p /etc/aralert
    GEN_PASS=`openssl rand -hex 12`
    GEN_KEY=`openssl rand -hex 24`
    cat > "$CONF_FILE" <<EOF
APP_NAME="ARALert"
APP_USER="aralert"
APP_GROUP="aralert"
APP_DIR="/opt/aralert"
VENV_DIR="/opt/aralert/backend/venv"
BACKUP_DIR="/var/backups/aralert"
LOG_DIR="/var/log/aralert"
PID_FILE="/run/aralert/aralert-gunicorn.pid"
MAINT_FLAG="/opt/aralert/maintenance.enable"
MAINT_PAGE="/opt/aralert/maintenance.html"
APP_URL="http://127.0.0.1/"
HEALTH_URL="http://127.0.0.1:8000/api/health/"
DB_NAME="aralert"
DB_USER="aralert_user"
DB_PASS="$GEN_PASS"
DB_HOST="localhost"
DB_PORT="5432"
SECRET_KEY="$GEN_KEY"
EOF
    chown root:root "$CONF_FILE"
    chmod 600 "$CONF_FILE"
fi
chmod 600 "$CONF_FILE"
. "$CONF_FILE"

echo "=== Installing $APP_NAME ==="

echo "[1/6] Checking required packages..."
PKGS="postgresql python3 python3-venv libpq-dev nginx curl tar openssl procps iproute2 rsync"
UPDATED=0
for P in $PKGS; do
    if ! dpkg -s "$P" >/dev/null 2>&1; then
        if [ $UPDATED -eq 0 ]; then
            apt-get update -y && UPDATED=1
        fi
        apt-get install -y "$P" || { echo "Error: Failed to install $P."; exit 1; }
    fi
done

echo "[2/6] Setting up user $APP_USER and PostgreSQL ($DB_NAME)..."
if ! grep -q "^$APP_USER:" /etc/passwd; then
    useradd -r -m -d "$APP_DIR" -s /usr/sbin/nologin "$APP_USER"
fi
mkdir -p "$APP_DIR" "$BACKUP_DIR" "$LOG_DIR" /run/aralert
systemctl start postgresql || { echo "Error: PostgreSQL failed to start (check systemd in WSL)."; exit 1; }

if su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\" | grep -q 1"; then
    su - postgres -c "psql -c \"ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';\"" >/dev/null
else
    su - postgres -c "psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';\"" >/dev/null
fi
if ! su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\" | grep -q 1"; then
    su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\"" >/dev/null
fi
su - postgres -c "psql -d $DB_NAME -c \"GRANT ALL ON SCHEMA public TO $DB_USER;\"" >/dev/null

echo "[3/6] Copying application files to $APP_DIR..."
rsync -a --delete --exclude='.git' --exclude='backend/venv' --exclude='backend/.venv' \
    --exclude='frontend/node_modules' --exclude='frontend/node_modules_old' \
    --exclude='backend/db.sqlite3' "$SOURCE_DIR/" "$APP_DIR/" || { echo "Error: File copy failed."; exit 1; }

cat > "$APP_DIR/backend/.env" <<EOF
SECRET_KEY=$SECRET_KEY
DEBUG=False
ALLOWED_HOSTS=localhost,127.0.0.1
USE_SQLITE=False
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
CORS_ALLOWED_ORIGINS=http://localhost,http://127.0.0.1
CSRF_TRUSTED_ORIGINS=http://localhost,http://127.0.0.1
EOF
echo "<!DOCTYPE html><html><body><h1>Service Temporarily Unavailable</h1><p>ARALert is under maintenance.</p></body></html>" > "$MAINT_PAGE"

echo "[4/6] Setting up Python backend and running migrations..."
if [ ! -f "$VENV_DIR/bin/gunicorn" ]; then
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install -q -r "$APP_DIR/backend/requirements.txt" || { echo "Error: pip install failed."; exit 1; }
fi
cd "$APP_DIR/backend"
"$VENV_DIR/bin/python" manage.py migrate --noinput && "$VENV_DIR/bin/python" seed_superadmin.py || { echo "Error: Migration failed."; exit 1; }
"$VENV_DIR/bin/python" manage.py collectstatic --noinput >/dev/null 2>&1

echo "[5/6] Setting permissions and starting services..."
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR" "$LOG_DIR" /run/aralert
find "$APP_DIR" -type d -exec chmod 750 {} \;
chmod 600 "$APP_DIR/backend/.env"
chmod 644 "$MAINT_PAGE"
usermod -a -G "$APP_GROUP" www-data

cat > /etc/systemd/system/aralert.service <<EOF
[Unit]
Description=ARALert Gunicorn Server
After=network.target postgresql.service
[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
RuntimeDirectory=aralert
WorkingDirectory=$APP_DIR/backend
EnvironmentFile=$APP_DIR/backend/.env
ExecStart=$VENV_DIR/bin/gunicorn config.wsgi:application --workers 3 --bind 127.0.0.1:8000 --pid $PID_FILE
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/sites-available/aralert <<EOF
server {
    listen 80;
    server_name _;
    root $APP_DIR/frontend/dist;
    index index.html;
    error_page 503 @maint;
    location @maint { root $APP_DIR; rewrite ^(.*)$ /maintenance.html break; }
    location ~ ^/(api|admin)/ {
        if (-f $MAINT_FLAG) { return 503; }
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
    }
    location /static/ { alias $APP_DIR/backend/staticfiles/; }
    location / { if (-f $MAINT_FLAG) { return 503; } try_files \$uri \$uri/ /index.html; }
}
EOF
ln -sf /etc/nginx/sites-available/aralert /etc/nginx/sites-enabled/aralert
rm -f /etc/nginx/sites-enabled/default
systemctl daemon-reload && systemctl enable aralert >/dev/null 2>&1
systemctl restart aralert && systemctl restart nginx

echo "[6/6] Verifying $APP_NAME..."
TRIES=0
HEALTH_OK=0
while [ $TRIES -lt 5 ]; do
    if curl -s "$HEALTH_URL" | grep -q "healthy"; then
        HEALTH_OK=1
        break
    fi
    sleep 2
    TRIES=$(( $TRIES + 1 ))
done

HTTP_CODE=`curl -s -o /dev/null -w "%{http_code}" "$APP_URL"`
if [ $HEALTH_OK -eq 1 ] && [ "$HTTP_CODE" = "200" ]; then
    echo "SUCCESS: $APP_NAME is installed and responding (HTTP $HTTP_CODE)."
    exit 0
fi
echo "FAILURE: $APP_NAME verification failed (HTTP $HTTP_CODE)."
exit 1
