// deadline_test.c - Deadline scheduling test for xv6
#include "types.h"
#include "stat.h"
#include "user.h"

void
deadline_task(int id, uint period, uint runtime)
{
  struct sched_param param;
  param.sched_priority = 50;
  param.runtime = runtime;
  param.deadline = period;
  param.period = period;
  
  if(sched_setscheduler(0, 3, &param) < 0) { // SCHED_DEADLINE = 3
    printf(1, "Task %d: Failed to set deadline scheduler\n", id);
    exit();
  }
  
  printf(1, "Periodic Task %d: Period=%d, Exec=%d started\n", id, period, runtime);
  
  int i;
  for(i = 0; i < 10; i++) {
    int sum = 0, j;
    int work_units = runtime / 100000;
    if(work_units > 10000) work_units = 10000; // Limit work
    
    for(j = 0; j < work_units; j++) {
      sum += j;
    }
    
    printf(1, "Task %d completed job %d\n", id, i);
    sleep(10); // Yield equivalent
  }
  
  printf(1, "Task %d completed all jobs\n", id);
  exit();
}

int
main(int argc, char *argv[])
{
  int pid, i;
  uint periods[] = {50000000, 100000000, 200000000};    // Periods
  uint runtimes[] = {20000000, 30000000, 40000000};     // Runtimes
  
  printf(1, "Real-time Deadline Scheduling Test\n");
  
  // Create periodic tasks
  for(i = 0; i < 3; i++) {
    pid = fork();
    if(pid == 0) {
      deadline_task(i, periods[i], runtimes[i]);
    } else if(pid < 0) {
      printf(1, "Fork failed for task %d\n", i);
    }
  }
  
  // Wait for all tasks to complete
  for(i = 0; i < 3; i++) {
    wait();
  }
  
  printf(1, "Deadline scheduling test completed\n");
  exit();
}

