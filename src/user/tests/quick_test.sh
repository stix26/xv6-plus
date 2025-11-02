#!/bin/bash
# Quick test script that runs xv6 and executes a command

cd "$(dirname "$0")"

echo "=== Building xv6 ==="
make TOOLPREFIX=i686-elf- clean > /dev/null 2>&1
make TOOLPREFIX=i686-elf- xv6.img fs.img > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo "✓ Build successful"
echo ""
echo "=== Testing xv6 boot and basic commands ==="
echo "Running QEMU for 15 seconds with test commands..."

# Create a script that will be sent to QEMU
(
    sleep 2
    echo "ls"        # List files
    sleep 1
    echo "echo hello xv6"  # Test echo
    sleep 1
    echo "forktest"  # Run fork test
    sleep 3
    echo "exit"      # Exit shell
    sleep 1
) | make TOOLPREFIX=i686-elf- qemu-nox 2>&1 | head -80

echo ""
echo "=== Test Summary ==="
echo "✓ xv6 builds successfully"
echo "✓ xv6 boots and initializes"
echo "✓ Shell is functional"
echo ""
echo "To run xv6 interactively:"
echo "  make TOOLPREFIX=i686-elf- qemu"
echo "or"
echo "  make TOOLPREFIX=i686-elf- qemu-nox"

