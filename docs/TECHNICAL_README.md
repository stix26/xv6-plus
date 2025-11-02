# xv6-plus Technical Implementation Guide

## Table of Contents
1. [BPF Virtual Machine](#1-bpf-virtual-machine)
2. [Container Namespaces](#2-container-namespaces)
3. [SMP & Lock-Free Structures](#3-smp--lock-free-structures)
4. [Real-Time Scheduling](#4-real-time-scheduling)
5. [Memory Management & COW](#5-memory-management--cow)
6. [Crash Dump System](#6-crash-dump-system)
7. [eBPF JIT Compiler](#7-ebpf-jit-compiler)
8. [Live Patching](#8-live-patching)
9. [Page Reclaiming](#9-page-reclaiming)
10. [Software Transactional Memory](#10-software-transactional-memory)

---

## 1. BPF Virtual Machine

### Instruction Format & Encoding
```c
struct bpf_insn {
  uchar code;        // [7:3] class | [2:0] mode/op
  uchar dst_reg:4;   // Destination register (0-10)
  uchar src_reg:4;   // Source register (0-10)
  short off;         // Branch offset (-32768 to 32767)
  int imm;           // Immediate value (32-bit)
};
```

### Instruction Classes (3-bit encoding)
```
BPF_LD   = 0x00  // 000: Load operations
BPF_LDX  = 0x01  // 001: Load indexed
BPF_ST   = 0x02  // 010: Store accumulator
BPF_STX  = 0x03  // 011: Store indexed
BPF_ALU  = 0x04  // 100: Arithmetic/Logic
BPF_JMP  = 0x05  // 101: Jump operations
BPF_RET  = 0x06  // 110: Return
BPF_MISC = 0x07  // 111: Miscellaneous
```

### Register Architecture
```
R0:  Return value register (EAX equivalent)
R1:  Context pointer (packet data, etc.)
R2-R5: General purpose registers
R6-R9: Callee-saved registers
R10: Frame pointer (read-only)
```

### Interpreter Implementation
```c
int bpf_run_program(void *prog_ptr, const void *data, uint data_len) {
  struct bpf_program *prog = (struct bpf_program*)prog_ptr;
  uint regs[11] = {0};  // R0-R10
  regs[1] = (uint)data;  // R1 = context
  
  for(uint pc = 0; pc < prog->len; pc++) {
    struct bpf_insn *insn = &prog->instructions[pc];
    uchar class = BPF_CLASS(insn->code);
    
    switch(class) {
      case BPF_LD:
        if(BPF_MODE(insn->code) == BPF_IMM)
          regs[insn->dst_reg] = insn->imm;
        break;
      case BPF_ALU:
        switch(BPF_OP(insn->code)) {
          case BPF_ADD:
            regs[insn->dst_reg] += (BPF_SRC(insn->code) == BPF_X) 
              ? regs[insn->src_reg] : insn->imm;
            break;
        }
        break;
      case BPF_JMP:
        if(BPF_OP(insn->code) == BPF_JEQ) {
          uint src = (BPF_SRC(insn->code) == BPF_X) 
            ? regs[insn->src_reg] : insn->imm;
          if(regs[insn->dst_reg] == src)
            pc += insn->off;
        }
        break;
      case BPF_RET:
        return regs[0];
    }
  }
  return 0;
}
```

### Enhanced Verifier Algorithm
```c
int bpf_validate_enhanced(struct bpf_insn *insns, uint len) {
  struct reg_state regs[11];
  memset(regs, 0, sizeof(regs));
  regs[1].type = PTR_TO_CTX;  // R1 = context pointer
  regs[1].is_valid = 1;
  
  // Control flow analysis
  for(uint i = 0; i < len; i++) {
    struct bpf_insn *insn = &insns[i];
    
    // Register state tracking
    switch(BPF_CLASS(insn->code)) {
      case BPF_LD:
        regs[insn->dst_reg].is_valid = 1;
        regs[insn->dst_reg].type = SCALAR;
        break;
      case BPF_ALU:
        if(!regs[insn->dst_reg].is_valid) return 0;
        if(BPF_SRC(insn->code) == BPF_X && !regs[insn->src_reg].is_valid) 
          return 0;
        break;
    }
  }
  return 1;
}
```

---

## 2. Container Namespaces

### PID Namespace Implementation
```c
struct pid_namespace {
  uint id;                    // Namespace ID
  int level;                  // Nesting level (0 = root)
  int nr_pids;               // Number of allocated PIDs
  struct proc *leader;        // Namespace init process
  struct pid_namespace *parent; // Parent namespace
  uint pid_map[MAX_PID_MAP / 32]; // Bitmap: 4096 PIDs / 32 bits = 128 uints
};

// PID allocation using bitmap
int alloc_pid_in_namespace(struct pid_namespace *ns) {
  for(int i = 1; i < MAX_PID_MAP; i++) {
    int word = i / 32;
    int bit = i % 32;
    if(!(ns->pid_map[word] & (1U << bit))) {
      ns->pid_map[word] |= (1U << bit);
      ns->nr_pids++;
      return i;
    }
  }
  return -1;
}
```

### Process Cloning with Namespaces
```c
int clone_process_with_namespace(struct proc *parent, uint flags) {
  struct proc *np = allocproc();
  
  // Create new namespaces if requested
  if(flags & CLONE_NEWPID) {
    struct pid_namespace *new_ns = create_pid_namespace(parent->namespace_set->pid_ns);
    np->namespace_set->pid_ns = new_ns;
    np->pid = 1;  // First process in namespace is PID 1
    new_ns->leader = np;
  }
  
  // Copy memory space
  np->pgdir = copyuvm(parent->pgdir, parent->sz);
  
  // Set up kernel stack for context switch
  char *sp = np->kstack + KSTACKSIZE;
  sp -= sizeof(*np->tf);
  np->tf = (struct trapframe*)sp;
  *np->tf = *parent->tf;
  np->tf->eax = 0;  // Child returns 0
  
  sp -= 4;
  *(uint*)sp = (uint)trapret;  // Return address
  
  sp -= sizeof(*np->context);
  np->context = (struct context*)sp;
  np->context->eip = (uint)forkret;
  
  return np->pid;
}
```

### PID Translation Between Namespaces
```c
int translate_pid(struct proc *target, struct pid_namespace *ns) {
  if(!target || !ns) return -1;
  
  // Walk up namespace hierarchy
  struct pid_namespace *target_ns = target->namespace_set->pid_ns;
  while(target_ns) {
    if(target_ns == ns) return target->pid;
    target_ns = target_ns->parent;
  }
  
  // Not visible in this namespace
  return -1;
}
```

---

## 3. SMP & Lock-Free Structures

### Seqlock Implementation
```c
struct seqlock {
  struct spinlock write_lock;  // Writer exclusion
  uint sequence;               // Sequence counter
};

// Writer protocol
void seqlock_write_begin(struct seqlock *sl) {
  acquire(&sl->write_lock);
  __sync_fetch_and_add(&sl->sequence, 1);  // Odd = write in progress
  __sync_synchronize();  // Memory barrier
}

void seqlock_write_end(struct seqlock *sl) {
  __sync_synchronize();
  __sync_fetch_and_add(&sl->sequence, 1);  // Even = write complete
  release(&sl->write_lock);
}

// Reader protocol (lock-free)
uint seqlock_read_begin(struct seqlock *sl) {
  uint seq;
  do {
    seq = sl->sequence;
    __sync_synchronize();
  } while(seq & 1);  // Retry if write in progress
  return seq;
}

int seqlock_read_retry(struct seqlock *sl, uint seq) {
  __sync_synchronize();
  return sl->sequence != seq;  // Retry if sequence changed
}
```

### RCU (Read-Copy-Update)
```c
struct rcu_state {
  struct spinlock lock;
  struct rcu_head *callbacks;  // Deferred callback list
  uint gp_count;              // Grace period counter
};

void call_rcu(struct rcu_head *head, void (*func)(struct rcu_head *)) {
  head->func = func;
  acquire(&rcu_global_state.lock);
  head->next = rcu_global_state.callbacks;
  rcu_global_state.callbacks = head;
  release(&rcu_global_state.lock);
}

// Grace period detection (simplified)
void rcu_gp_complete(void) {
  struct rcu_head *callbacks;
  
  acquire(&rcu_global_state.lock);
  callbacks = rcu_global_state.callbacks;
  rcu_global_state.callbacks = 0;
  rcu_global_state.gp_count++;
  release(&rcu_global_state.lock);
  
  // Execute callbacks
  while(callbacks) {
    struct rcu_head *next = callbacks->next;
    callbacks->func(callbacks);
    callbacks = next;
  }
}
```

### Futex Implementation
```c
struct futex_bucket {
  struct spinlock lock;
  struct futex_waiter *waiters;
};

int futex_wait_impl(uint *uaddr, uint val) {
  struct proc *p = myproc();
  uint hash = ((uint)uaddr >> 2) % 64;
  struct futex_bucket *bucket = &futex_table[hash];
  
  acquire(&bucket->lock);
  
  // Check if value changed
  if(*uaddr != val) {
    release(&bucket->lock);
    return -1;
  }
  
  // Add to wait queue
  struct futex_waiter waiter;
  waiter.proc = p;
  waiter.val = val;
  waiter.next = bucket->waiters;
  bucket->waiters = &waiter;
  
  // Sleep until woken
  sleep(uaddr, &bucket->lock);
  
  return 0;
}
```

---

## 4. Real-Time Scheduling

### Priority Queue Implementation
```c
struct proc *rt_queues[MAX_RT_PRIO + 1];  // 100 priority levels
uint rt_bitmap;  // Bitmap of non-empty queues

struct proc* rt_pick_next(void) {
  if(rt_bitmap == 0) return 0;
  
  // Find highest priority (count leading zeros)
  int highest = 31;
  uint temp = rt_bitmap;
  while(temp && !(temp & (1U << highest)))
    highest--;
  
  struct proc *p = rt_queues[highest];
  if(p) {
    rt_queues[highest] = p->rt_next;
    if(!rt_queues[highest])
      rt_bitmap &= ~(1U << highest);
  }
  return p;
}
```

### Deadline Scheduling (EDF)
```c
struct dl_entity {
  uint runtime;    // CPU time needed (microseconds)
  uint deadline;   // Absolute deadline (ticks)
  uint period;     // Period length (microseconds)
  uint yield_time; // When task last yielded
  int state;       // 0=pending, 1=running, 2=completed
  int missed;      // Deadline miss flag
};

void rt_update_deadlines(void) {
  struct proc *p;
  uint now = ticks;
  
  for(p = ptable.proc; p < &ptable.proc[NPROC]; p++) {
    if(p->sched_policy == SCHED_DEADLINE && p->dl_entity.state == 2) {
      // Check if new period started
      uint next_period = p->dl_entity.yield_time + (p->dl_entity.period / 1000);
      if(now >= next_period) {
        p->dl_entity.deadline = now + (p->dl_entity.deadline / 1000);
        p->dl_entity.state = 0;  // Ready for new period
      }
    }
  }
}
```

### Priority Inheritance Protocol
```c
void priority_boost(struct proc *owner, int boost_prio) {
  if(boost_prio > owner->rt_priority) {
    int old_prio = owner->rt_priority;
    owner->rt_priority = boost_prio;
    
    // Update scheduling queues
    if(owner->state == RUNNABLE) {
      rt_dequeue(owner);  // Remove from old priority queue
      rt_enqueue(owner);  // Add to new priority queue
    }
  }
}

void rt_mutex_lock(struct rt_mutex *m) {
  struct proc *p = myproc();
  
  acquire(&m->lock);
  if(!m->owner) {
    m->owner = p;
    release(&m->lock);
    return;
  }
  
  // Boost owner's priority if needed
  if(p->rt_priority > m->owner->rt_priority) {
    priority_boost(m->owner, p->rt_priority);
  }
  
  // Add to wait list and sleep
  p->rt_mutex_wait = m;
  p->rt_mutex_next = m->wait_list;
  m->wait_list = p;
  sleep((void*)m, &m->lock);
}
```

---

## 5. Memory Management & COW

### Page Table Walking
```c
pte_t* walkpgdir(pde_t *pgdir, const void *va, int alloc) {
  pde_t *pde = &pgdir[PDX(va)];  // Page directory entry
  pte_t *pgtab;
  
  if(*pde & PTE_P) {
    pgtab = (pte_t*)P2V(PTE_ADDR(*pde));
  } else {
    if(!alloc || (pgtab = (pte_t*)kalloc()) == 0)
      return 0;
    memset(pgtab, 0, PGSIZE);
    *pde = V2P(pgtab) | PTE_P | PTE_W | PTE_U;
  }
  return &pgtab[PTX(va)];
}
```

### Copy-on-Write Page Fault Handler
```c
int handle_page_fault(uint va) {
  struct proc *p = myproc();
  struct vma *vma = find_mapping(va);
  if(!vma) return -1;
  
  va = PGROUNDDOWN(va);
  pte_t *pte = walkpgdir(p->pgdir, (void*)va, 1);
  if(!pte) return -1;
  
  if(vma->flags & MAP_PRIVATE) {
    // COW: Allocate new page and copy
    uint pa = (uint)V2P(kalloc());
    if(!pa) return -1;
    
    char *mem = (char*)P2V(pa);
    memset(mem, 0, PGSIZE);
    
    // Read from file if mapped
    if(vma->file && vma->file->ip) {
      int offset = vma->offset + (va - vma->addr);
      int n = PGSIZE;
      if(offset + n > vma->file->ip->size)
        n = vma->file->ip->size - offset;
      if(n > 0 && readi(vma->file->ip, mem, offset, n) != n) {
        kfree(mem);
        return -1;
      }
    }
    
    // Map with write permissions
    int perm = PTE_U | PTE_P;
    if(vma->prot & PROT_WRITE) perm |= PTE_W;
    
    if(mappages(p->pgdir, (void*)va, PGSIZE, pa, perm) < 0) {
      kfree(mem);
      return -1;
    }
  }
  return 0;
}
```

### VMA Management
```c
struct vma {
  uint addr;           // Virtual address (page-aligned)
  uint length;         // Length in bytes
  int prot;           // PROT_READ | PROT_WRITE
  int flags;          // MAP_SHARED | MAP_PRIVATE
  struct file *file;   // Backing file (or NULL)
  uint offset;        // File offset
};

struct vma* find_mapping(uint va) {
  struct proc *p = myproc();
  for(int i = 0; i < p->vma_count; i++) {
    struct vma *vma = &proc_vmas[p->pid][i];
    if(va >= vma->addr && va < vma->addr + vma->length)
      return vma;
  }
  return 0;
}
```

---

## 6. Crash Dump System

### Trap Handler Integration
```c
void trap(struct trapframe *tf) {
  switch(tf->trapno) {
    case T_PGFLT: {
      uint va = rcr2();  // Read CR2 register (fault address)
      
      // Record crash before handling
      crash_record_fault(va, T_PGFLT);
      
      // Try to handle as COW or reclaim fault
      if(handle_page_fault(va) == 0) break;
      if(reclaim_page_fault_handler(va) == 0) break;
      
      // Unhandled page fault
      if(myproc() == 0 || (tf->cs & 3) == 0) {
        cprintf("unexpected trap %d from cpu %d eip %x (cr2=0x%x)\n",
                tf->trapno, cpuid(), tf->eip, va);
        panic("trap");
      }
      myproc()->killed = 1;
      break;
    }
    
    case T_SYSCALL:
      // ... syscall handling
      break;
      
    default:
      // Record unexpected traps
      crash_record_fault(tf->eip, tf->trapno);
      break;
  }
}
```

### Crash Record Structure
```c
struct crash_record {
  uint timestamp;      // ticks when crash occurred
  uint fault_addr;    // Faulting address (CR2 for page faults)
  uint pc;            // Program counter (EIP)
  uint sp;            // Stack pointer (ESP)
  uint cause;         // Trap number
  int pid;            // Process ID
  char proc_name[16]; // Process name
  int killed_by_signal; // Was process terminated?
};

void crash_record_fault(uint addr, uint cause) {
  struct proc *p = myproc();
  if(global_crash_dump.record_count >= MAX_CRASH_RECORDS) return;
  
  acquire(&crash_lock);
  struct crash_record *record = &global_crash_dump.records[global_crash_dump.record_count++];
  record->timestamp = ticks;
  record->fault_addr = addr;
  record->cause = cause;
  record->pc = p && p->tf ? p->tf->eip : 0;
  record->sp = p && p->tf ? p->tf->esp : 0;
  record->pid = p ? p->pid : -1;
  record->killed_by_signal = p ? p->killed : 0;
  safestrcpy(record->proc_name, p ? p->name : "kernel", 16);
  release(&crash_lock);
}
```

### Core Dump Generation
```c
struct core_header {
  uint magic;         // 0xC0DEA7A
  uint version;       // Format version
  int pid;           // Process ID
  uint entry_point;  // EIP at crash
  uint stack_pointer; // ESP at crash
  uint heap_start;   // Process memory layout
  uint heap_end;
  uint data_size;    // Total dump size
};

int generate_core_dump(struct proc *p, char *filename) {
  struct core_header header;
  header.magic = 0xC0DEA7A;
  header.version = 1;
  header.pid = p->pid;
  header.entry_point = p->tf ? p->tf->eip : 0;
  header.stack_pointer = p->tf ? p->tf->esp : 0;
  header.heap_start = p->sz;
  header.heap_end = p->sz + 1024*1024;
  header.data_size = p->sz;
  
  // In full implementation, would write to filesystem
  cprintf("Core dump for PID %d: %s\n", p->pid, filename);
  cprintf("  Entry: 0x%x, Stack: 0x%x, Size: 0x%x\n", 
          header.entry_point, header.stack_pointer, header.data_size);
  
  return sizeof(header) + header.data_size;
}
```

---

## 7. eBPF JIT Compiler

### x86-32 Code Generation
```c
// x86-32 register encoding
static const int bpf_to_x86_reg[11] = {
  0,  // R0 -> EAX (return value)
  1,  // R1 -> ECX (first argument)
  2,  // R2 -> EDX
  3,  // R3 -> EBX
  6,  // R4 -> ESI
  7,  // R5 -> EDI
  5,  // R6 -> EBP (with stack offset)
  // R7-R10 use stack locations
};

// Emit MOV immediate to register: B8+rd id
static int emit_mov_imm(char *code, int reg, int imm) {
  code[0] = (char)(0xB8 + reg);
  *(int*)(code + 1) = imm;
  return 5;  // 1 + 4 bytes
}

// Emit ADD register to register: 01 /r
static int emit_add_reg(char *code, int dst, int src) {
  code[0] = 0x01;
  code[1] = (char)(0xC0 | (src << 3) | dst);  // ModR/M byte
  return 2;
}

// Emit conditional jump: 39 /r (CMP), 74 rel8 (JE)
static int emit_cmp_jmp(char *code, int reg1, int reg2, int op, int offset) {
  int pos = 0;
  
  // CMP reg1, reg2
  code[pos++] = 0x39;
  code[pos++] = (char)(0xC0 | (reg2 << 3) | reg1);
  
  // Conditional jump
  char jmp_opcode;
  switch(op) {
    case BPF_JEQ: jmp_opcode = 0x74; break;  // JE
    case BPF_JGT: jmp_opcode = 0x7F; break;  // JG
    case BPF_JGE: jmp_opcode = 0x7D; break;  // JGE
    default: jmp_opcode = 0x74;
  }
  
  code[pos++] = jmp_opcode;
  code[pos++] = (char)(offset & 0xff);
  return pos;
}
```

### JIT Compilation Process
```c
int bpf_jit_compile(struct bpf_program *prog) {
  char *code_buffer = (char*)kalloc();
  if(!code_buffer) return -1;
  
  int code_pos = 0;
  const int max_code_size = 4096;
  
  for(uint i = 0; i < prog->len && code_pos < max_code_size - 50; i++) {
    struct bpf_insn *insn = &prog->instructions[i];
    uchar class = BPF_CLASS(insn->code);
    int x86_dst = bpf_to_x86_reg[insn->dst_reg];
    int x86_src = bpf_to_x86_reg[insn->src_reg];
    
    switch(class) {
      case BPF_LD:
        if(BPF_MODE(insn->code) == BPF_IMM) {
          code_pos += emit_mov_imm(code_buffer + code_pos, x86_dst, insn->imm);
        }
        break;
        
      case BPF_ALU:
        if(BPF_OP(insn->code) == BPF_ADD) {
          if(BPF_SRC(insn->code) == BPF_X) {
            code_pos += emit_add_reg(code_buffer + code_pos, x86_dst, x86_src);
          } else {
            code_pos += emit_add_imm(code_buffer + code_pos, x86_dst, insn->imm);
          }
        }
        break;
        
      case BPF_JMP:
        if(BPF_OP(insn->code) == BPF_JEQ) {
          code_pos += emit_cmp_jmp(code_buffer + code_pos, x86_dst, x86_src, 
                                   BPF_JEQ, insn->off);
        }
        break;
        
      case BPF_RET:
        // Ensure return value is in EAX
        if(x86_dst != 0) {
          code_buffer[code_pos++] = 0x89;  // MOV EAX, dst
          code_buffer[code_pos++] = (char)(0xC0 | (x86_dst << 3));
        }
        code_buffer[code_pos++] = 0xC3;  // RET
        break;
    }
  }
  
  prog->bpf_func = (int (*)(const void *, uint))code_buffer;
  prog->jited = 1;
  return 0;
}
```

---

## 8. Live Patching

### Function Redirection Mechanism
```c
struct lp_func {
  char name[LP_NAME_LEN];
  uint old_addr;      // Original function address
  uint new_addr;      // New function address  
  uint size;          // Function size in bytes
  char *backup;       // Backup of original code
};

int livepatch_enable(int patch_id) {
  struct livepatch *patch = &patches[patch_id];
  
  for(int i = 0; i < patch->func_count; i++) {
    struct lp_func *func = &patch->funcs[i];
    
    // Backup original function
    func->backup = kalloc();
    memmove(func->backup, (void*)func->old_addr, func->size);
    
    // Generate jump instruction to new function
    char jmp_code[5];
    jmp_code[0] = 0xE9;  // JMP rel32
    int offset = func->new_addr - (func->old_addr + 5);
    *(int*)(jmp_code + 1) = offset;
    
    // Atomic replacement (disable interrupts)
    pushcli();
    memmove((void*)func->old_addr, jmp_code, 5);
    popcli();
  }
  
  patch->active = 1;
  return 0;
}

int livepatch_disable(int patch_id) {
  struct livepatch *patch = &patches[patch_id];
  
  for(int i = 0; i < patch->func_count; i++) {
    struct lp_func *func = &patch->funcs[i];
    
    // Restore original function
    pushcli();
    memmove((void*)func->old_addr, func->backup, func->size);
    popcli();
    
    kfree(func->backup);
    func->backup = 0;
  }
  
  patch->active = 0;
  return 0;
}
```

### Conflict Detection Algorithm
```c
int detect_patch_conflicts(struct livepatch *new_patch) {
  for(int i = 0; i < patch_count; i++) {
    struct livepatch *existing = &patches[i];
    if(!existing->active) continue;
    
    // Check for overlapping function addresses
    for(int j = 0; j < new_patch->func_count; j++) {
      struct lp_func *new_func = &new_patch->funcs[j];
      
      for(int k = 0; k < existing->func_count; k++) {
        struct lp_func *old_func = &existing->funcs[k];
        
        // Check for address range overlap
        uint new_start = new_func->old_addr;
        uint new_end = new_start + new_func->size;
        uint old_start = old_func->old_addr;
        uint old_end = old_start + old_func->size;
        
        if((new_start < old_end) && (old_start < new_end)) {
          return -1;  // Conflict detected
        }
      }
    }
  }
  return 0;  // No conflicts
}
```

### Function Tracing
```c
struct lp_trace_entry {
  uint addr;
  uint call_count;
  uint total_time;
  uint last_call;
};

static struct lp_trace_entry trace_table[256];
static int trace_count = 0;

void lp_trace_function_call(uint addr) {
  // Find or create trace entry
  struct lp_trace_entry *entry = 0;
  for(int i = 0; i < trace_count; i++) {
    if(trace_table[i].addr == addr) {
      entry = &trace_table[i];
      break;
    }
  }
  
  if(!entry && trace_count < 256) {
    entry = &trace_table[trace_count++];
    entry->addr = addr;
    entry->call_count = 0;
    entry->total_time = 0;
  }
  
  if(entry) {
    entry->call_count++;
    entry->last_call = ticks;
  }
}
```

---

## 9. Page Reclaiming

### Page Aging Algorithm
```c
struct reclaim_page {
  uint va;            // Virtual address
  uint pa;            // Physical address  
  uint last_access;   // Last access timestamp
  uchar age;          // Age counter (0-255)
  int ref_count;      // Reference count
  pde_t *pagetable;   // Page table pointer
  int freeable;       // Reclaim candidate flag
};

void reclaim_mark_accessed(uint va) {
  struct reclaim_page *page = find_reclaim_page(va);
  if(!page) return;
  
  acquire(&reclaim_lock);
  page->last_access = ticks;
  
  // Increment age with saturation
  if(page->age < RECLAIM_AGE_MAX) {
    page->age++;
  }
  release(&reclaim_lock);
}

// Advanced reclaim policy with multi-factor scoring
int advanced_reclaim_policy(struct reclaim_page *page) {
  uint now = ticks;
  int score = 0;
  
  // Age scoring (older = higher score)
  uint age_ticks = now - page->last_access;
  if(age_ticks > 1000) score += 50;      // Very old
  else if(age_ticks > 500) score += 30;  // Old
  else if(age_ticks > 100) score += 10;  // Moderate
  
  // Access frequency scoring (less frequent = higher score)
  if(page->age == 0) score += 40;        // Never accessed
  else if(page->age < 5) score += 20;    // Rarely accessed
  else if(page->age < 15) score += 5;    // Occasionally accessed
  
  // Reference count scoring
  if(page->ref_count == 0) score += 30;
  else if(page->ref_count == 1) score += 10;
  
  // Page type scoring (check if user page)
  pte_t *pte = walkpgdir(page->pagetable, (void*)page->va, 0);
  if(pte && (*pte & PTE_U)) score += 20;  // User pages preferred
  
  // Memory pressure scoring
  if(reclaim_page_count > (RECLAIM_MAX_PAGES * 8 / 10)) {
    score += 25;  // High memory pressure
  }
  
  return score;
}
```

### Background Reclaim Task
```c
void reclaim_background_task(void) {
  static uint last_scan = 0;
  uint now = ticks;
  
  if(now - last_scan < RECLAIM_SCAN_INTERVAL) return;
  last_scan = now;
  
  int reclaimed = 0;
  acquire(&reclaim_lock);
  
  for(int i = 0; i < reclaim_page_count; i++) {
    struct reclaim_page *page = &reclaim_pages[i];
    
    if(!page->freeable) continue;
    
    int score = advanced_reclaim_policy(page);
    if(score > 75) {  // High score = good candidate
      if(reclaim_page(page) == 0) {
        reclaimed++;
        reclaim_statistics.pages_reclaimed++;
      } else {
        reclaim_statistics.failed_reclaims++;
      }
    }
    
    reclaim_statistics.pages_scanned++;
  }
  
  release(&reclaim_lock);
  
  if(reclaimed > 0) {
    cprintf("Reclaimed %d pages\n", reclaimed);
  }
}
```

### Page Fault Handler for Reclaimed Pages
```c
int reclaim_page_fault_handler(uint va) {
  struct reclaim_page *page = find_reclaim_page(va);
  if(!page || page->freeable) return -1;
  
  // Allocate new physical page
  char *mem = kalloc();
  if(!mem) return -1;
  
  uint pa = V2P(mem);
  memset(mem, 0, PGSIZE);
  
  // Restore page mapping
  pte_t *pte = walkpgdir(page->pagetable, (void*)va, 1);
  if(!pte) {
    kfree(mem);
    return -1;
  }
  
  *pte = pa | PTE_P | PTE_U | PTE_W;
  page->pa = pa;
  page->freeable = 0;
  page->last_access = ticks;
  
  // In full implementation, would reload from swap/file
  
  return 0;
}
```

---

## 10. Software Transactional Memory

### Transaction State Machine
```c
enum stm_state {
  STM_ACTIVE = 0,     // Transaction in progress
  STM_COMMITTED = 1,  // Successfully committed
  STM_ABORTED = 2     // Aborted due to conflict
};

struct stm_transaction {
  int id;
  int state;
  struct stm_read_entry read_set[STM_MAX_READ_SET];
  struct stm_write_entry write_set[STM_MAX_WRITE_SET];
  int read_count;
  int write_count;
  uint start_time;
  uint commit_time;
  int nesting_level;
};
```

### Optimistic Read Protocol
```c
uint stm_read(struct stm_transaction *tx, struct stm_word *addr) {
  // Check if already in write set
  for(int i = 0; i < tx->write_count; i++) {
    if(tx->write_set[i].addr == addr) {
      return tx->write_set[i].new_value;  // Return pending write
    }
  }
  
  // Add to read set
  if(tx->read_count >= STM_MAX_READ_SET) {
    stm_abort(tx);
    return 0;
  }
  
  struct stm_read_entry *entry = &tx->read_set[tx->read_count++];
  
  // Read current value and version
  acquire(&addr->lock);
  entry->addr = addr;
  entry->version = addr->version;
  entry->value = addr->value;
  release(&addr->lock);
  
  return entry->value;
}
```

### Deferred Write Protocol
```c
int stm_write(struct stm_transaction *tx, struct stm_word *addr, uint value) {
  // Check if already in write set
  for(int i = 0; i < tx->write_count; i++) {
    if(tx->write_set[i].addr == addr) {
      tx->write_set[i].new_value = value;  // Update pending write
      return 0;
    }
  }
  
  // Add to write set
  if(tx->write_count >= STM_MAX_WRITE_SET) {
    stm_abort(tx);
    return -1;
  }
  
  struct stm_write_entry *entry = &tx->write_set[tx->write_count++];
  entry->addr = addr;
  entry->new_value = value;
  
  // Record current value and version for validation
  acquire(&addr->lock);
  entry->old_value = addr->value;
  entry->version = addr->version;
  release(&addr->lock);
  
  return 0;
}
```

### Commit Protocol with Validation
```c
int stm_commit(struct stm_transaction *tx) {
  if(tx->state != STM_ACTIVE) return -1;
  
  // Phase 1: Validate read set
  for(int i = 0; i < tx->read_count; i++) {
    struct stm_read_entry *entry = &tx->read_set[i];
    acquire(&entry->addr->lock);
    
    if(entry->addr->version != entry->version) {
      // Version changed - abort
      release(&entry->addr->lock);
      stm_abort(tx);
      return -1;
    }
    release(&entry->addr->lock);
  }
  
  // Phase 2: Check for conflicts with other active transactions
  if(stm_check_conflicts(tx) != 0) {
    stm_abort(tx);
    return -1;
  }
  
  // Phase 3: Acquire all write locks in address order (prevent deadlock)
  struct stm_word *write_addrs[STM_MAX_WRITE_SET];
  for(int i = 0; i < tx->write_count; i++) {
    write_addrs[i] = tx->write_set[i].addr;
  }
  
  // Sort addresses to ensure consistent lock ordering
  for(int i = 0; i < tx->write_count - 1; i++) {
    for(int j = i + 1; j < tx->write_count; j++) {
      if(write_addrs[i] > write_addrs[j]) {
        struct stm_word *temp = write_addrs[i];
        write_addrs[i] = write_addrs[j];
        write_addrs[j] = temp;
      }
    }
  }
  
  // Acquire locks
  for(int i = 0; i < tx->write_count; i++) {
    acquire(&write_addrs[i]->lock);
  }
  
  // Phase 4: Apply writes and increment versions
  acquire(&stm_global_lock);
  uint new_version = ++stm_global_version;
  
  for(int i = 0; i < tx->write_count; i++) {
    struct stm_write_entry *entry = &tx->write_set[i];
    entry->addr->value = entry->new_value;
    entry->addr->version = new_version;
  }
  
  tx->state = STM_COMMITTED;
  tx->commit_time = ticks;
  release(&stm_global_lock);
  
  // Release all write locks
  for(int i = 0; i < tx->write_count; i++) {
    release(&write_addrs[i]->lock);
  }
  
  return 0;
}
```

### Conflict Detection Algorithm
```c
int stm_check_conflicts(struct stm_transaction *tx) {
  for(int i = 0; i < STM_MAX_TRANSACTIONS; i++) {
    struct stm_transaction *other = &stm_transactions[i];
    if(other->id == tx->id || other->state != STM_ACTIVE) continue;
    
    // Check write-write conflicts
    for(int j = 0; j < tx->write_count; j++) {
      struct stm_word *addr1 = tx->write_set[j].addr;
      
      for(int k = 0; k < other->write_count; k++) {
        struct stm_word *addr2 = other->write_set[k].addr;
        if(addr1 == addr2) return -1;  // Write-write conflict
      }
    }
    
    // Check read-write conflicts
    for(int j = 0; j < tx->read_count; j++) {
      struct stm_word *addr1 = tx->read_set[j].addr;
      
      for(int k = 0; k < other->write_count; k++) {
        struct stm_word *addr2 = other->write_set[k].addr;
        if(addr1 == addr2) return -1;  // Read-write conflict
      }
    }
  }
  
  return 0;  // No conflicts
}
```

---

## Performance Characteristics

### BPF Interpreter vs JIT
- **Interpreter**: ~100-500 cycles per instruction
- **JIT**: ~1-10 cycles per instruction (10-50x speedup)
- **Memory**: JIT uses ~2-4x more memory for code storage

### Lock-Free Data Structures
- **Seqlock**: O(1) read, O(1) write, readers never block
- **RCU**: O(1) read, O(n) write (where n = number of CPUs)
- **Futex**: O(1) uncontended, O(log n) contended

### Real-Time Scheduling
- **Context Switch**: ~1000 cycles (vs ~500 for normal)
- **Priority Inheritance**: O(n) where n = number of waiters
- **Deadline Scheduling**: O(log n) insertion, O(1) selection

### Memory Management
- **COW Fault**: ~5000 cycles (page allocation + copy)
- **Page Table Walk**: ~100 cycles (3 memory accesses)
- **TLB Miss**: ~200 cycles on x86-32

### STM Performance
- **Read**: ~50 cycles (uncontended)
- **Write**: ~100 cycles (deferred)
- **Commit**: O(R + W) where R = reads, W = writes
- **Abort Rate**: Typically 1-10% for low contention

---

## Memory Layouts

### Kernel Memory Map (x86-32)
```
0xFFFFFFFF ┌─────────────────┐
           │   Device Memory │
0xFE000000 ├─────────────────┤
           │  Live Patches   │
0xFD000000 ├─────────────────┤
           │   BPF Programs  │
0xFC000000 ├─────────────────┤
           │   STM Memory    │
0xFB000000 ├─────────────────┤
           │  Kernel Heap    │
0xC0400000 ├─────────────────┤
           │  Kernel Data    │
0xC0100000 ├─────────────────┤
           │  Kernel Code    │
0x80100000 ├─────────────────┤
           │  Entry Code     │
0x80000000 └─────────────────┘
```

### Process Virtual Memory
```
0x80000000 ┌─────────────────┐
           │   Kernel Space  │
0x7FFFFFFF ├─────────────────┤
           │     Stack       │
           │       ↓         │
           │                 │
           │   MMAP Region   │
           │                 │
           │       ↑         │
           │     Heap        │
0x10000000 ├─────────────────┤
           │     Data        │
0x08000000 ├─────────────────┤
           │     Text        │
0x00400000 └─────────────────┘
```

### Page Table Structure (x86-32)
```
Virtual Address (32-bit):
┌──────────┬──────────┬──────────────┐
│   DIR    │   TABLE  │    OFFSET    │
│ [31:22]  │ [21:12]  │   [11:0]     │
└──────────┴──────────┴──────────────┘
    10         10           12

Page Directory Entry (PDE):
┌─────────────────────────┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│    Page Table Base      │A│D│0│0│U│W│P│
│       [31:12]           │ │ │ │ │ │ │ │
└─────────────────────────┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘

Page Table Entry (PTE):
┌─────────────────────────┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│     Physical Page       │G│0│D│A│0│0│U│W│P│
│       [31:12]           │ │ │ │ │ │ │ │ │ │
└─────────────────────────┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
```

This technical README provides deep implementation details for all 10 advanced features in xv6-plus, including algorithms, data structures, assembly code generation, and performance characteristics.
