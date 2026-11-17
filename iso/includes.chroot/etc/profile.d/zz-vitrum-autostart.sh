# Live session: start Vitrum on the first console after autologin.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(id -u)" -ne 0 ]; then
    clear
    # Installed systems sign in at Vitrum's own sign-in screen. The console
    # is signed in automatically, so it must never be left at a shell.
    signin=""
    if [ -e /etc/vitrum/sign-in-required ]; then
        signin=1
        export VITRUM_START_LOCKED=1
        trap '' INT QUIT TSTP
    fi
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
        # A normal sign-out after a real session: start a fresh one (at the
        # sign-in screen on installed systems).
        [ "$rc" -eq 0 ] && [ $(( $(date +%s) - start )) -gt 20 ] && continue
        clear
        echo
        echo "  Vitrum couldn't start the display."
        echo
        echo "  Restart the computer, press Esc while it starts, and choose"
        echo "  \"Start Vitrum (safe graphics)\" or \"Start Vitrum (basic display)\"."
        echo "  In VMware, turning \"Accelerate 3D graphics\" on or off in the"
        echo "  virtual machine's Display settings can also help."
        echo
        if [ -n "$signin" ]; then
            echo "  Press Enter to try again."
            echo "  Details are in $log"
            read -r _ || sleep 5
            exit 0
        fi
        echo "  Type 'vitrum-session' to try again, or 'sudo reboot' to restart."
        echo "  Details are in $log"
        echo
        break
    done
fi
