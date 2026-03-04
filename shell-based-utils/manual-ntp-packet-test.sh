#!/bin/bash
printf '\x1b' | dd bs=1 count=1 2>/dev/null | \
  cat - <(head -c 47 /dev/zero) | \
  nc -u -w2 129.6.15.28 123 | \
  hexdump -C
