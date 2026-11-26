#!/bin/bash
# aralert-start-stop.sh: Start and stop ARALert services in the correct order
# Authors: L. Omadto, N.J. Alcovindas, J.B. Licup (BSIT)
# Usage: sudo scripts/aralert-start-stop.sh --start | --stop | --restart
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

CONF_FILE="/etc/aralert/aralert.conf"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo scripts/aralert-start-stop.sh --start | --stop | --restart"
    echo "Options:"
    echo "  --start     Start postgresql, aralert, and nginx in order"
    echo "  --stop      Stop nginx, aralert, and postgresql in reverse order"
    echo "  --restart   Stop and start all services in order"
    echo "  --help      Show this help message"
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Error: Provide one option (--start, --stop, --restart, or --help)."
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

START_LIST="postgresql aralert nginx"
STOP_LIST="nginx aralert postgresql"

case "$1" in
    --start|start)
        if systemctl is-active --quiet aralert; then
            echo "Error: $APP_NAME is already running. Refusing to start a second copy."
            exit 2
        fi

        echo "Starting $APP_NAME services in order..."
        for S in $START_LIST; do
            echo "Starting $S..."
            systemctl start "$S"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to start $S."
                exit 1
            fi
        done

        TRIES=0
        while [ $TRIES -lt 5 ]; do
            if curl -s "$HEALTH_URL" | grep -q "healthy"; then
                echo "SUCCESS: All $APP_NAME services started ($START_LIST)."
                exit 0
            fi
            sleep 2
            TRIES=$(( $TRIES + 1 ))
        done
        echo "Error: Services started, but health check failed."
        exit 1
        ;;
    --stop|stop)
        echo "Stopping $APP_NAME services in reverse order..."
        PIDS=`pgrep -u "$APP_USER"`
        for P in $PIDS; do
            kill -CONT $P 2>/dev/null
        done
        for S in $STOP_LIST; do
            echo "Stopping $S..."
            systemctl stop "$S"
        done
        rm -f "$PID_FILE"
        echo "SUCCESS: All $APP_NAME services stopped ($STOP_LIST)."
        ;;
    --restart|restart)
        for S in $STOP_LIST; do
            systemctl stop "$S"
        done
        for S in $START_LIST; do
            systemctl start "$S" || exit 1
        done
        echo "SUCCESS: All $APP_NAME services restarted."
        ;;
    *)
        echo "Error: Invalid option $1. Use --start, --stop, --restart, or --help."
        exit 2
        ;;
esac

exit 0
