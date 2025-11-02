#!/bin/bash
# Check prerequisites for xv6 feature development

echo "=== xv6 Feature Development Prerequisites Check ==="
echo ""

# Check for cross-compiler
echo -n "Checking cross-compiler (i686-elf-gcc)... "
if command -v i686-elf-gcc &> /dev/null; then
    echo "✓ Found: $(i686-elf-gcc --version | head -n1)"
else
    echo "✗ Not found"
    echo "  Install with: brew install i686-elf-gcc"
fi

# Check for QEMU
echo -n "Checking QEMU... "
if command -v qemu-system-i386 &> /dev/null; then
    echo "✓ Found: $(qemu-system-i386 --version | head -n1)"
else
    echo "✗ Not found"
    echo "  Install with: brew install qemu"
fi

# Check for GDB (for debugging)
echo -n "Checking GDB... "
if command -v gdb &> /dev/null; then
    echo "✓ Found: $(gdb --version | head -n1)"
else
    echo "✗ Not found (optional, for debugging)"
    echo "  Install with: brew install gdb"
fi

# Check build status
echo ""
echo -n "Checking xv6 build status... "
cd "$(dirname "$0")/.."
if [ -f "kernel" ] && [ -f "xv6.img" ] && [ -f "fs.img" ]; then
    echo "✓ Built"
    echo "  Kernel: $(ls -lh kernel | awk '{print $5}')"
    echo "  Disk images: $(ls -lh *.img | wc -l) found"
else
    echo "✗ Not built"
    echo "  Build with: make TOOLPREFIX=i686-elf-"
fi

echo ""
echo "=== Ready for development! ==="
echo "Start with Phase 1 features from FEATURE_ROADMAP.md"

