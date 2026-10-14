#!/bin/zsh
# Run while the failing connection is selected. This only reads configuration
# and sends bounded diagnostic requests; it changes no DNS, routes, or Wi-Fi state.
set -uo pipefail
report="$(mktemp /tmp/dynamite-network.XXXXXX)"
{
    date
    /usr/sbin/scutil --nwi
    /sbin/route -n get default
    /usr/sbin/scutil --nc list
    /usr/sbin/networksetup -getdnsservers Wi-Fi
    /usr/sbin/networksetup -getwebproxy Wi-Fi
    /usr/sbin/networksetup -getsecurewebproxy Wi-Fi
    /usr/sbin/scutil --dns
    network_gateway="$(/sbin/route -n get default 2>/dev/null | awk '$1 == "gateway:" { print $2; exit }')"
    if [[ -n "$network_gateway" ]]; then
        /sbin/ping -n -c 1 -t 2 -W 1000 "$network_gateway"
    fi
    /sbin/ping -n -c 1 -t 2 -W 1000 9.9.9.9
    /usr/bin/dig @9.9.9.9 example.com +time=2 +tries=1
    /usr/bin/curl -I --connect-timeout 3 --max-time 6 https://example.com
} > "$report" 2>&1
print "Saved read-only network checks to $report"
