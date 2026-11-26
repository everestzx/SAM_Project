#!/bin/bash
# aralert-maintenance.sh: Switch ARALert to HTTP 503 Maintenance Mode and back
# Authors: L. Omadto, N.J. Alcovindas, J.B. Licup (BSIT)
# Usage: sudo scripts/aralert-maintenance.sh --on | --off | --status
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONF_FILE="/etc/aralert/aralert.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo scripts/aralert-maintenance.sh --on | --off | --status"
    echo "Options:"
    echo "  --on       Enable maintenance mode (HTTP 503 Temporarily Unavailable)"
    echo "  --off      Disable maintenance mode (HTTP 200 Live)"
    echo "  --status   Show whether maintenance mode is ON or OFF"
    echo "  --help     Show this help message"
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Error: Provide one option (--on, --off, --status, or --help)."
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

. "$CONF_FILE"

case "$1" in
    --on|on)
        echo "Enabling maintenance mode..."
        echo "<!DOCTYPE html><html><body style='font-family:sans-serif;text-align:center;padding:10%;'><h1>Service Temporarily Unavailable</h1><p>ARALert is undergoing scheduled maintenance. Please try again shortly.</p></body></html>" > "$MAINT_PAGE"
        touch "$MAINT_FLAG"
        chmod 644 "$MAINT_PAGE" "$MAINT_FLAG"
        systemctl start nginx
        HTTP_CODE=`curl -s -o /dev/null -w "%{http_code}" "$APP_URL"`
        if [ "$HTTP_CODE" = "503" ]; then
            echo "SUCCESS: Maintenance mode is ON (HTTP $HTTP_CODE - Temporarily Unavailable)."
        else
            echo "Error: Expected HTTP 503, got HTTP $HTTP_CODE."
            exit 1
        fi
        ;;
    --off|off)
        echo "Disabling maintenance mode..."
        rm -f "$MAINT_FLAG"
        HTTP_CODE=`curl -s -o /dev/null -w "%{http_code}" "$APP_URL"`
        if [ "$HTTP_CODE" = "200" ]; then
            echo "SUCCESS: Maintenance mode is OFF (HTTP $HTTP_CODE - Live)."
        else
            echo "Error: Expected HTTP 200, got HTTP $HTTP_CODE."
            exit 1
        fi
        ;;
    --status|status)
        if [ -f "$MAINT_FLAG" ]; then
            echo "STATUS: Maintenance mode is ON (HTTP 503)."
        else
            echo "STATUS: Maintenance mode is OFF (Live)."
        fi
        ;;
    *)
        echo "Error: Invalid option $1. Use --on, --off, --status, or --help."
        exit 2
        ;;
esac

exit 0
