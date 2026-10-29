#!/usr/bin/env bash
set -euo pipefail

readonly root=/logs
readonly state_dir=$root/.state
readonly logrotate_conf=/etc/logrotate-h5ai.conf
readonly logrotate_state=$state_dir/logrotate.status
readonly marker=$state_dir/last-rotation
readonly lock=$state_dir/tick.lock

fail() { printf 'h5ai-logs: %s\n' "$*" >&2; exit 1; }

validate() {
    : "${TZ:=Asia/Seoul}"
    : "${PGID:=911}"
    : "${LOG_READ_GID:=$PGID}"
    : "${LOG_ROTATE_INTERVAL_DAYS:=1}"
    : "${LOG_RETENTION_DAYS:=30}"
    export TZ

    [[ $TZ != *[$'\n\r']* ]] || fail 'TZ must be a timezone name'
    # shellcheck disable=SC2016
    php -r '$zones = DateTimeZone::listIdentifiers(DateTimeZone::ALL_WITH_BC); exit(in_array(getenv("TZ"), $zones, true) ? 0 : 1);' || fail "unknown TZ: $TZ"
    [[ $LOG_ROTATE_INTERVAL_DAYS =~ ^[0-9]{1,5}$ ]] || fail 'LOG_ROTATE_INTERVAL_DAYS must be an integer from 1 to 36500'
    [[ $LOG_RETENTION_DAYS =~ ^[0-9]{1,5}$ ]] || fail 'LOG_RETENTION_DAYS must be an integer from 1 to 36500'
    (( 10#$LOG_ROTATE_INTERVAL_DAYS >= 1 && 10#$LOG_ROTATE_INTERVAL_DAYS <= 36500 )) || fail 'LOG_ROTATE_INTERVAL_DAYS must be from 1 to 36500'
    (( 10#$LOG_RETENTION_DAYS >= 1 && 10#$LOG_RETENTION_DAYS <= 36500 )) || fail 'LOG_RETENTION_DAYS must be from 1 to 36500'
    (( 10#$LOG_RETENTION_DAYS >= 10#$LOG_ROTATE_INTERVAL_DAYS )) || fail 'LOG_RETENTION_DAYS must be at least LOG_ROTATE_INTERVAL_DAYS'
    [[ $LOG_READ_GID =~ ^[0-9]{1,10}$ ]] || fail 'LOG_READ_GID must be a numeric group ID'
    (( 10#$LOG_READ_GID <= 2147483647 )) || fail 'LOG_READ_GID is out of range'
    LOG_ROTATE_INTERVAL_DAYS=$((10#$LOG_ROTATE_INTERVAL_DAYS))
    LOG_RETENTION_DAYS=$((10#$LOG_RETENTION_DAYS))
    LOG_READ_GID=$((10#$LOG_READ_GID))
}

prepare() {
    validate
    getent group "$LOG_READ_GID" >/dev/null || groupadd -g "$LOG_READ_GID" "h5ai-logs-$LOG_READ_GID"
    [[ ! -L $root ]] || fail "$root must not be a symlink"
    mkdir -p "$root"
    for dir in "$root/nginx" "$root/php" "$state_dir"; do
        [[ ! -L $dir ]] || fail "$dir must not be a symlink"
        mkdir -p "$dir"
    done
    chown 0:"$LOG_READ_GID" "$root" "$root/nginx" "$root/php"
    chmod 0750 "$root" "$root/nginx" "$root/php"
    chown 0:0 "$state_dir"
    chmod 0700 "$state_dir"

    for file in "$root/nginx/access.log" "$root/nginx/error.log" "$root/php/error.log"; do
        [[ ! -L $file ]] || fail "$file must not be a symlink"
        if [[ -e $file && ! -f $file ]]; then fail "$file must be a regular file"; fi
        if [[ -e $file && $(stat -c %h "$file") != 1 ]]; then fail "$file must not be hard-linked"; fi
        touch "$file"
        chown 0:"$LOG_READ_GID" "$file"
        chmod 0640 "$file"
    done

    [[ ! -L $marker ]] || fail "$marker must not be a symlink"
    if [[ -e $marker && ! -f $marker ]]; then fail "$marker must be a regular file"; fi
    if [[ -e $marker && $(stat -c %h "$marker") != 1 ]]; then fail "$marker must not be hard-linked"; fi
    if [[ ! -e $marker ]]; then
        printf 'last=%s\n' "$(date +%F)" > "$marker"
    fi
    chown 0:0 "$marker"
    chmod 0600 "$marker"

    for file in "$lock" "$logrotate_state"; do
        [[ ! -L $file ]] || fail "$file must not be a symlink"
        if [[ -e $file && ! -f $file ]]; then fail "$file must be a regular file"; fi
        if [[ -e $file && $(stat -c %h "$file") != 1 ]]; then fail "$file must not be hard-linked"; fi
        touch "$file"
        chown 0:0 "$file"
        chmod 0600 "$file"
    done

    cat > "$logrotate_conf" <<EOF
/logs/nginx/access.log /logs/nginx/error.log /logs/php/error.log {
    daily
    rotate -1
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d-%s
    create 0640 root $LOG_READ_GID
    compress
    delaycompress
}
EOF
    chmod 0644 "$logrotate_conf"

    mkdir -p /etc/h5ai-crontabs
    printf 'SHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n* * * * * TZ=%s LOG_READ_GID=%s LOG_ROTATE_INTERVAL_DAYS=%s LOG_RETENTION_DAYS=%s /usr/local/bin/h5ai-logs tick >>/proc/1/fd/1 2>&1\n' \
        "$TZ" "$LOG_READ_GID" "$LOG_ROTATE_INTERVAL_DAYS" "$LOG_RETENTION_DAYS" > /etc/h5ai-crontabs/root
    chmod 0600 /etc/h5ai-crontabs/root
}

fd_targets() {
    # shellcheck disable=SC2016
    php -r '
        $files = glob("/proc/" . $argv[1] . "/fd/*");
        if (!$files) exit(1);
        foreach ($files as $fd) {
            $target = @readlink($fd);
            if ($target !== false) echo $target, "\n";
        }
    ' "${1:-[0-9]*}"
}

supervisor_has_archive_fd() {
    local target targets
    targets=$(fd_targets "$supervisor_pid") || fail 'could not inspect Supervisor file descriptors'
    while IFS= read -r target; do
        case "$target" in
            /logs/nginx/access.log-????????-??????????|/logs/nginx/error.log-????????-??????????|/logs/php/error.log-????????-??????????) return 0 ;;
        esac
    done <<< "$targets"
    return 1
}

archive_epoch() {
    local name=${1##*/}
    [[ $name =~ ^(access|error)\.log-[0-9]{8}-([0-9]{10,})(\.gz)?$ ]] || return 1
    printf '%s' "${BASH_REMATCH[2]}"
}

supervisor_archive_date() {
    local target name date targets
    targets=$(fd_targets "$supervisor_pid") || fail 'could not inspect Supervisor file descriptors'
    while IFS= read -r target; do
        case "$target" in
            /logs/nginx/access.log-*|/logs/nginx/error.log-*|/logs/php/error.log-*) ;;
            *) continue ;;
        esac
        name=${target##*/}
        if [[ $name =~ ^(access|error)\.log-([0-9]{8})-[0-9]{10,}(\.gz)?$ ]]; then
            date=${BASH_REMATCH[2]}
            printf '%s' "${date:0:4}-${date:4:2}-${date:6:2}"
            return 0
        fi
    done <<< "$targets"
    return 1
}

any_archive_open() {
    local file targets
    targets=$(fd_targets) || fail 'could not inspect open log files'
    while IFS= read -r file; do
        case "$file" in
            /logs/nginx/access.log-*|/logs/nginx/error.log-*|/logs/php/error.log-*) ;;
            *) continue ;;
        esac
        [[ -f $file && ! -L $file ]] || continue
        archive_epoch "$file" >/dev/null || continue
        return 0
    done <<< "$targets"
    return 1
}

reopen_supervisor() {
    local deadline=$((SECONDS + 5))
    kill -USR2 "$supervisor_pid" || return 1
    while (( SECONDS <= deadline )); do
        supervisor_has_archive_fd || return 0
        sleep 0.1
    done
    return 1
}

write_marker() {
    local value=$1 temporary
    temporary=$(mktemp "$state_dir/last-rotation.XXXXXX")
    printf '%s\n' "$value" > "$temporary"
    mv -f "$temporary" "$marker"
}

recover_rotation() {
    local previous=$1 archive_date
    if [[ $previous == pending=* ]]; then
        archive_date=${previous#pending=}
    else
        archive_date=$(supervisor_archive_date) || return 1
        previous="pending=$archive_date"
        write_marker "$previous"
    fi
    reopen_supervisor || fail 'Supervisor still has a rotated log open; retrying next minute'
    write_marker "last=$archive_date"
    printf 'Recovered log rotation dated %s\n' "$archive_date"
}

expire_archives() {
    local now cutoff file epoch targets
    now=$(date +%s)
    cutoff=$((now - 10#$LOG_RETENTION_DAYS * 86400))
    targets=$'\n'"$(fd_targets)"$'\n' || fail 'could not inspect open log files'
    for file in /logs/nginx/access.log-[0-9]* /logs/nginx/error.log-[0-9]* /logs/php/error.log-[0-9]*; do
        [[ -f $file && ! -L $file ]] || continue
        epoch=$(archive_epoch "$file") || continue
        (( epoch <= cutoff )) || continue
        if [[ $targets != *$'\n'"$file"$'\n'* ]]; then
            rm -- "$file"
            printf 'Removed expired log %s\n' "$file"
        fi
    done
}

tick_locked() {
    local current last due
    [[ ! -L $marker ]] || fail "$marker must not be a symlink"
    [[ -f $marker ]] || fail 'log state is missing; run h5ai-logs prepare'
    IFS= read -r current < "$marker"
    if [[ $current == pending=* ]] || supervisor_has_archive_fd; then
        recover_rotation "$current"
        IFS= read -r current < "$marker"
    elif [[ $current != last=* ]]; then
        fail 'invalid log rotation state'
    fi

    last=${current#last=}
    if [[ $current == pending=* ]]; then
        last=${current#pending=}
    fi
    # shellcheck disable=SC2016
    due=$(php -r '$tz = new DateTimeZone(getenv("TZ")); $date = DateTimeImmutable::createFromFormat("!Y-m-d", $argv[1], $tz); if (!$date) exit(1); echo $date->modify("+" . $argv[2] . " days")->format("Y-m-d");' "$last" "$LOG_ROTATE_INTERVAL_DAYS") || fail 'could not calculate next rotation date'
    if [[ $(date +%F) < $due ]]; then
        expire_archives
        return
    fi
    if any_archive_open; then
        printf 'A rotated log is still open; deferring rotation\n'
        return
    fi

    if logrotate --force --state "$logrotate_state" "$logrotate_conf"; then
        write_marker "pending=$(date +%F)"
        reopen_supervisor || fail 'Supervisor did not reopen the rotated logs; retrying next minute'
        write_marker "last=$(date +%F)"
        printf 'Rotated service logs for %s\n' "$(date +%F)"
    else
        fail 'logrotate failed; rotation state was not advanced'
    fi
    expire_archives
}

tick() {
    validate
    IFS= read -r supervisor_pid < /run/supervisord.pid || fail 'Supervisor PID file is missing'
    [[ $supervisor_pid =~ ^[1-9][0-9]*$ && -d /proc/$supervisor_pid/fd ]] || fail 'Supervisor is not running'
    exec 9>"$lock"
    flock -n 9 || return $?
    tick_locked
}

case ${1:-} in
    prepare) prepare ;;
    tick) tick ;;
    *) fail 'usage: h5ai-logs prepare|tick' ;;
esac
