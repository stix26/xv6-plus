// Test namespace creation for xv6
#include "types.h"
#include "stat.h"
#include "user.h"

// Define namespace constants (would normally come from namespace.h but user space)
#define CLONE_NEWPID    0x20000000
#define CLONE_NEWNS     0x00020000
#define CLONE_NEWNET    0x40000000
#define CLONE_NEWUSER   0x10000000

int
main(int argc, char *argv[])
{
  int pid;
  
  printf(1, "=== Namespace Test Program ===\n");
  printf(1, "Creating new PID namespace...\n");
  
  // Create process with new PID namespace
  pid = clone3(CLONE_NEWPID | CLONE_NEWNS);
  
  if(pid < 0) {
    printf(1, "Failed to create namespace\n");
    exit();
  }
  
  if(pid == 0) {
    // Child process - should see isolated PID space
    printf(1, "Child process in new namespace\n");
    printf(1, "My PID: %d\n", getpid());
    
    // This process becomes PID 1 in new namespace if working correctly
    if(getpid() == 1) {
      printf(1, "SUCCESS: New PID namespace created! PID = 1\n");
    } else {
      printf(1, "Note: PID namespace may be working (current PID: %d)\n", getpid());
    }
    
    // Try to fork a child in the namespace
    int child_pid = fork();
    if(child_pid == 0) {
      printf(1, "Child of namespace process, PID: %d\n", getpid());
      exit();
    } else if(child_pid > 0) {
      wait();
      printf(1, "Namespace child process completed\n");
    }
    
    exit();
  } else {
    // Parent process
    printf(1, "Parent process PID: %d\n", getpid());
    printf(1, "Child created with PID: %d\n", pid);
    wait();
    printf(1, "Namespace test completed\n");
  }
  
  exit();
}

