# Live session: start Vitrum on the first console after autologin.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(id -u)" -ne 0 ]; then
    clear
    log="${XDG_RUNTIME_DIR:-/tmp}/vitrum-session.log"
    serial=""
    grep -qw vitrum.serial-log /proc/cmdline 2>/dev/null && [ -w /dev/ttyS0 ] && serial=/dev/ttyS0
    if [ -n "$serial" ]; then
        # Boot tests: stream the session and app logs to the serial console.
        touch "$log" "${XDG_RUNTIME_DIR:-/tmp}/vitrum-apps.log"
        ( tail -n +1 -F "$log" "${XDG_RUNTIME_DIR:-/tmp}/vitrum-apps.log" > "$serial" 2>/dev/null & )
    fi
    while :; do
        start=$(date +%s)
        vitrum-session
        rc=$?
        if [ -n "$serial" ]; then
            { echo "=== vitrum-session exited with $rc ==="; cat "$log"; echo "=== end of log ==="; } > "$serial" 2>/dev/null
        fi
        # A normal sign-out after a real session: start a fresh one.
        [ "$rc" -eq 0 ] && [ $(( $(date +%s) - start )) -gt 20 ] && continue
        echo
        echo "Vitrum could not start (exit code $rc). Last lines of $log:"
        echo
        tail -n 30 "$log" 2>/dev/null
        echo
        echo "Type 'vitrum-session' to try again."
        break
    done
fi
