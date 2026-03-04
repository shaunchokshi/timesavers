#!/bin/bash
ip link add wg0 type wireguard
wg setconf wg0 /etc/wireguard/wg0.conf
ip -4 address add 10.100.0.1/24 dev wg0
ip -6 address add fdcc:ad94:bacf:61a4:fa00::1/64 dev wg0
ip link set mtu 1420 up dev wg0
