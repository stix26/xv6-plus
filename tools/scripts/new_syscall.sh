#!/bin/bash
# Helper script to add a new system call to xv6
# Usage: ./scripts/new_syscall.sh <syscall_name> [syscall_number]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <syscall_name> [syscall_number]"
    echo "Example: $0 getprocs 22"
    exit 1
fi

SYSCALL_NAME=$1
SYSCALL_NUM=${2:-22}  # Default to 22 if not provided
UPPER_NAME=$(echo "$SYSCALL_NAME" | tr '[:lower:]' '[:upper:]')

cd "$(dirname "$0")/.."

echo "Adding system call: $SYSCALL_NAME (number: $SYSCALL_NUM)"
echo ""

# Check if syscall number already exists
if grep -q "SYS_$SYSCALL_NAME" syscall.h 2>/dev/null; then
    echo "Error: System call $SYSCALL_NAME already exists!"
    exit 1
fi

# Step 1: Add to syscall.h
echo "Step 1: Adding to syscall.h..."
if ! grep -q "#define SYS_$SYSCALL_NAME" syscall.h; then
    sed -i.bak "s/#define SYS_close.*/#define SYS_close   21\n#define SYS_$SYSCALL_NAME   $SYSCALL_NUM/" syscall.h
    echo "  ✓ Added to syscall.h"
else
    echo "  ⊗ Already in syscall.h"
fi

# Step 2: Add to syscall.c
echo "Step 2: Adding to syscall.c..."
if ! grep -q "extern int sys_$SYSCALL_NAME" syscall.c; then
    sed -i.bak "/extern int sys_close(void);/a\\
extern int sys_$SYSCALL_NAME(void);" syscall.c
    
    # Add to syscalls array
    sed -i.bak "/\\[SYS_close\\]/a\\
[SYS_$SYSCALL_NAME] sys_$SYSCALL_NAME," syscall.c
    echo "  ✓ Added to syscall.c"
else
    echo "  ⊗ Already in syscall.c"
fi

# Step 3: Add stub to sysproc.c
echo "Step 3: Adding stub to sysproc.c..."
if ! grep -q "sys_$SYSCALL_NAME" sysproc.c; then
    cat >> sysproc.c << EOF

int
sys_$SYSCALL_NAME(void)
{
  // TODO: Implement $SYSCALL_NAME
  return 0;
}
EOF
    echo "  ✓ Added stub to sysproc.c"
else
    echo "  ⊗ Already in sysproc.c"
fi

# Step 4: Add to user.h
echo "Step 4: Adding to user.h..."
if ! grep -q "$SYSCALL_NAME(" user.h; then
    sed -i.bak "/^int uptime(void);/a\\
int $SYSCALL_NAME(void);" user.h
    echo "  ✓ Added to user.h"
else
    echo "  ⊗ Already in user.h"
fi

# Step 5: Add to usys.S
echo "Step 5: Adding to usys.S..."
if ! grep -q "$SYSCALL_NAME:" usys.S; then
    sed -i.bak "/SYSCALL(uptime)/a\\
SYSCALL($SYSCALL_NAME)" usys.S
    echo "  ✓ Added to usys.S"
else
    echo "  ⊗ Already in usys.S"
fi

# Clean up backup files
rm -f syscall.h.bak syscall.c.bak sysproc.c.bak user.h.bak usys.S.bak 2>/dev/null

echo ""
echo "✓ System call $SYSCALL_NAME added!"
echo ""
echo "Next steps:"
echo "1. Implement sys_$SYSCALL_NAME() in sysproc.c"
echo "2. Create a user program to test it (e.g., ${SYSCALL_NAME}.c)"
echo "3. Add _$SYSCALL_NAME to UPROGS in Makefile"
echo "4. Rebuild: make TOOLPREFIX=i686-elf- fs.img"

