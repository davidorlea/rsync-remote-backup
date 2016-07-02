#!/bin/bash

function log_debug {
  log "debug" "$1"
}

function log_notice {
  log "notice" "$1"
}

function log_warning {
  log "warning" "$1"
}

function log_error {
  log "error" "$1"
}

function log {
  echo $2
  if [[ $SYSLOG = TRUE ]]; then
    logger -t "$PROG" -p "$1" "$2"
  fi
}

# Read command line parameters
for i in "$@"; do
  case $i in
    --include=*)
    INCLUDE="${i#*=}"
    shift
    ;;
    --exclude=*)
    EXCLUDE="${i#*=}"
    shift
    ;;
    --lock=*)
    LOCK="${i#*=}"
    shift
    ;;
    --transfer-log=*)
    LOG="${i#*=}"
    shift
    ;;
    --syslog)
    SYSLOG=TRUE
    shift
    ;;
    --destination=*)
    DESTINATION="${i#*=}"
    shift
    ;;
    --rsync-path=*)
    RSYNC="${i#*=}"
    shift
    ;;
  esac
done

PROG="Remote Backup"

# Validate command line parameters
if [[ -z $INCLUDE ]]; then
  log_error "Unable to start backup: Missing argument --include"
  exit 1
else
  if [[ ! -r "$INCLUDE" ]]; then
    log_error "Unable to start backup: Include file $INCLUDE not readable"
    exit 1
  fi
fi

if [[ -z $EXCLUDE ]]; then
  log_error "Unable to start backup: Missing argument --exclude"
  exit 1
else
  if [[ ! -r "$EXCLUDE" ]]; then
    log_error "Unable to start backup: Exclude file $EXCLUDE not readable"
    exit 1
  fi
fi

if [[ -z $LOCK ]]; then
  log_error "Unable to start backup: Missing argument --lock"
  exit 1
fi

if [[ -z $DESTINATION ]]; then
  log_error "Unable to start backup: Missing argument --destination"
  exit 1
fi

if [[ -z $RSYNC ]]; then
  RSYNC="/bin/rsync"
fi

# Check for already running backup process
if [[ ! -e $LOCK ]]; then
  echo $$ > "$LOCK"
else
  PID=$(cat "$LOCK")
  if kill -0 "$PID" >& /dev/null; then
    log_notice "Unable to start backup: Backup still running"
    exit 0
  else
    echo $$ > "$LOCK"
    log_warning "Previous backup appears to have not finished correctly"
  fi
fi

# Check for writable temporaray log file
if [[ -z $LOG ]]; then
  LOG=$(mktemp)
else
  if [[ ! -e "$LOG" ]]; then
    touch "$LOG"
  else
    > "$LOG"
  fi
fi

if [ $? != 0 ] || [ ! -w "$LOG" ]; then
  log_error "Unable to start backup: Log file $LOG not writable"
  exit 1
else
  log_notice "Created temporary transfer log file $LOG"
fi

# Start backup process
log_notice "Starting backup to $DESTINATION"
rsync --archive \
      --compress \
      --relative \
      --partial \
      --progress \
      --hard-links \
      --sparse \
      --numeric-ids \
      --delete \
      --delete-excluded \
      --verbose \
      --stats \
      --rsync-path=$RSYNC \
      --log-file=$LOG \
      --exclude-from=$EXCLUDE \
      --include-from=$INCLUDE \
      "/" "$DESTINATION"

STATUS=$?
TRANSFERRED_NUMBER=$(awk '/files transferred/ {print $8}' $LOG)
TRANSFERRED_SIZE=$(awk '/transferred file size/ {print $8, $9}' $LOG)

# Finish backup process and report status
if [ $STATUS = 0 ]; then
  log_notice "Transferred $TRANSFERRED_NUMBER file(s) ($TRANSFERRED_SIZE)"
  log_notice "Completed backup successfully"
else
  log_error "Aborted backup due to errors (see transfer log)"
fi

rm -f "$LOCK"
exit 0
