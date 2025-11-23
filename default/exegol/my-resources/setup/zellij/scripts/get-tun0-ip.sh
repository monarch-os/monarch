#!/bin/bash
ip -o -4 addr show dev tun0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || echo 'down'
