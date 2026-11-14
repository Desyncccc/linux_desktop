# Live session: start Vitrum on the first console after autologin.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(id -u)" -ne 0 ]; then
    clear
    while :; do
        vitrum-session
        rc=$?
        # 0 means the user signed out: start a fresh session.
        [ "$rc" -eq 0 ] && continue
        log="${XDG_RUNTIME_DIR:-/tmp}/vitrum-session.log"
        echo
        echo "Vitrum could not start (exit code $rc). Last lines of $log:"
        echo
        tail -n 25 "$log" 2>/dev/null
        echo
        echo "Type 'vitrum-session' to try again. Switch to another console with Ctrl+Alt+F2."
        break
    done
fi
