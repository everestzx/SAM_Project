#!/bin/bash
# aralert-pause.sh: Suspend ARALert processes with kill -STOP and resume with kill -CONT
# Authors: L. Omadto, N.J. Alcovindas, J.B. Licup (BSIT)
# Usage: sudo scripts/aralert-pause.sh --pause | --resume | --status
# Note: Assisted by AI tools (Section 5.6); reviewed and tested by the group.

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: sudo scripts/aralert-pause.sh --pause | --resume | --status"
    echo "Options:"
    echo "  --pause    Suspend Gunicorn processes with kill -STOP"
    echo "  --resume   Resume Gunicorn processes with kill -CONT"
    echo "  --status   Show process state (T = paused, S/R = running)"
    echo "  --help     Show this help message"
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Error: Provide one option (--pause, --resume, --status, or --help)."
    exit 2
fi

USER_ID=`id -u`
if [ $USER_ID -ne 0 ]; then
    echo "Error: Please run this script with sudo."
    exit 1
fi

PIDS=`pgrep -u aralert`
if [ "$PIDS" = "" ]; then
    echo "Error: No running ARALert processes found."
    exit 1
fi

case "$1" in
    --pause|pause)
        echo "Suspending ARALert processes with kill -STOP..."
        for PID in $PIDS; do
            kill -STOP $PID
        done
        sleep 1
        ps -u aralert -o pid,stat,comm
        echo "SUCCESS: ARALert processes are now PAUSED (state T)."
        ;;
    --resume|resume)
        echo "Resuming ARALert processes with kill -CONT..."
        for PID in $PIDS; do
            kill -CONT $PID
        done
        sleep 1
        ps -u aralert -o pid,stat,comm
        echo "SUCCESS: ARALert processes are now RESUMED."
        ;;
    --status|status)
        ps -u aralert -o pid,stat,comm
        ;;
    *)
        echo "Error: Invalid option $1. Use --pause, --resume, --status, or --help."
        exit 2
        ;;
esac

exit 0
