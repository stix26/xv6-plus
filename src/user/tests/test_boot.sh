#!/bin/bash
# Simple test script to verify xv6 boots
# This script runs QEMU briefly to check if the system boots

cd "$(dirname "$0")"

echo "Testing xv6 boot..."
echo "This will run QEMU for 5 seconds to verify boot process"
echo ""

# Run QEMU with output redirection and kill it after 5 seconds
(
    sleep 5
    pkill -f "qemu.*xv6" || true
) &

# Run QEMU in non-graphical mode
make TOOLPREFIX=i686-elf- qemu-nox 2>&1 | head -50 &
QEMU_PID=$!

# Wait for QEMU to output something or timeout
sleep 5
kill $QEMU_PID 2>/dev/null || true

echo ""
echo "If you saw xv6 boot messages above, the system built and boots successfully!"

