#!/bin/bash

### this is if you do not have / want to have tailscaled as a systemd service
### then you can add this script to run at login
### e.g. in crontab : crontab -e
### add: @reboot /path/to/tailscaled.sh

_evalBg() {
    eval "$@" &>/dev/null & disown;
}

cmd="~/go/bin/tailscaled"
_evalBg "${cmd}" --no-sandbox;
