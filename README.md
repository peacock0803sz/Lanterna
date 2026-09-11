# Lanterna

A list-style window switcher for macOS.

## Recovering the system's Cmd+Tab

Lanterna takes Cmd+Tab and Shift+Cmd+Tab away from the system while it runs and gives them back when it exits. After `kill -9` or a crash it cannot give them back, because SIGKILL leaves nothing running to do it, so both shortcuts stay off until something else puts them on.

Check that no Lanterna is running before doing anything else. Restoring writes the shortcuts back on without reading their current state, so running this while another Lanterna is up takes the hotkeys away from that process. Running more than one at a time is not supported.

```bash
pgrep -x Lanterna    # expect no output; run `pkill Lanterna` first if there is any
```

Then start Lanterna again and stop it cleanly, which lets its shutdown do the restoring.

```bash
./.build/debug/Lanterna &
sleep 1
pkill Lanterna
```

If the shortcuts are still off after that, log out and back in. The system's assignment is per login session.
