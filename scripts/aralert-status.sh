#!/bin/bash
# aralert-status.sh: Report ARALert service state, ports, CPU/RAM, and resources
# Authors: L. Omadto, N.J. Alcovindas, J.B. Licup (BSIT)
# Usage: sudo scripts/aralert-status.sh [--save FILE]
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONF_FILE="/etc/aralert/aralert.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo scripts/aralert-status.sh [--save FILE]"
    echo "Options:"
    echo "  --save FILE   Save the status report to a file"
    echo "  --help        Show this help message"
    exit 0
fi

USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

if [ "$1" = "--save" ] || [ "$1" = "-o" ]; then
    if [ -z "$2" ]; then
        echo "Error: Provide a file path after $1."
        exit 2
    fi
    "$0" > "$2"
    RC=$?
    cat "$2"
    chmod 640 "$2"
    echo ""
    echo "Saved report to $2"
    exit $RC
fi

if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
else
    APP_NAME="ARALert"
    MAINT_FLAG="/opt/aralert/maintenance.enable"
    HEALTH_URL="http://127.0.0.1:8000/api/health/"
fi

SERVICES="postgresql aralert nginx"
EXIT_CODE=0
NOW=`date`

echo "=== $APP_NAME Status Report ($NOW) ==="
echo ""
echo "1. SERVICE STATE"
for S in $SERVICES; do
    if systemctl is-active --quiet "$S"; then
        echo "  $S: RUNNING"
    else
        echo "  $S: STOPPED"
        EXIT_CODE=1
    fi
done

PAUSED=`ps -u aralert -o stat= 2>/dev/null | grep -c "^T"`
if [ $PAUSED -gt 0 ]; then
    echo "  Process State: PAUSED ($PAUSED processes in state T)"
    EXIT_CODE=1
fi

if [ -f "$MAINT_FLAG" ]; then
    echo "  Maintenance Mode: ON (HTTP 503)"
else
    echo "  Maintenance Mode: OFF (Live)"
fi

echo ""
echo "2. LISTENING PORTS (80, 8000, 5432)"
ss -tulpn | grep -E ":(80|8000|5432)\b"

echo ""
echo "3. PROCESS CPU AND MEMORY USAGE"
ps -eo pid,stat,%cpu,%mem,comm | grep -E "PID|gunicorn|nginx|postgres"

echo ""
echo "4. SYSTEM RESOURCES (top, free, df)"
top -bn1 | grep -E "^(top -|%Cpu)"
free -h
df -h /

echo ""
echo "5. HEALTH CHECK"
if curl -s --max-time 3 "$HEALTH_URL" | grep -q "healthy"; then
    echo "  $HEALTH_URL: HEALTHY"
else
    echo "  $HEALTH_URL: UNHEALTHY or PAUSED"
    EXIT_CODE=1
fi

exit $EXIT_CODE
