// top.s — ARM64 macOS assembly "top" clone for Apple Silicon
//
// IMPORTANT: Apple ARM64 variadic calling convention:
//   x0 = format string, ALL variadic args go on the stack at [sp, #0], [sp, #8], etc.
//   Non-variadic functions use normal x0-x7 register passing.
//
.global _main
.align 4

// ============================================================
// Constants
// ============================================================
.set HOST_CPU_LOAD_INFO,        3
.set HOST_CPU_LOAD_INFO_COUNT,  4
.set HOST_VM_INFO64,            4
.set HOST_VM_INFO64_COUNT,      40
.set PROC_PIDTASKALLINFO,       2
.set PROC_PIDTASKALLINFO_SIZE,  232

.set CPU_USER,   0
.set CPU_SYS,    4
.set CPU_IDLE,   8
.set CPU_NICE,   12

.set VM_FREE,       0
.set VM_ACTIVE,     4
.set VM_INACTIVE,   8
.set VM_WIRE,       12
.set VM_SPECULATIVE, 92
.set VM_COMPRESSOR, 128

.set PTINFO_OFFSET,   136
.set PBI_STATUS,      4
.set PBI_COMM,        48
.set PBI_NAME,        64
.set PTI_RESIDENT,    8
.set PTI_TOTAL_USER,  16
.set PTI_TOTAL_SYS,   24
.set PTI_NUMRUNNING,  88       // pti_numrunning: 0=sleeping, >0=running

.set SIDL,   1
.set SRUN,   2
.set SSLEEP, 3
.set SSTOP,  4
.set SZOMB,  5

.set SORT_PID,     0
.set SORT_CPU,     4
.set SORT_MEM,     8
.set SORT_STATUS,  12
.set SORT_NAME,    16
.set SORT_ENTRY,   48

.set MAX_PIDS,      2048
.set MAX_DISPLAY,   20

.set PREV_PID,      0
.set PREV_CPUTIME,  8
.set PREV_ENTRY,    16
.set MAX_PREV,      2048

// ============================================================
// Read-only strings (__TEXT,__cstring)
// ============================================================
.section __TEXT,__cstring,cstring_literals

fmt_clear:      .asciz "\033[2J\033[H"
fmt_procs:      .asciz "Processes: %d total, %d running, %d sleeping\n"
fmt_cpu:        .asciz "CPU usage: %d.%d%% user, %d.%d%% sys, %d.%d%% idle\n"
fmt_mem:        .asciz "PhysMem:   %lluM used, %lluM free\n"
fmt_header:     .asciz "\n\033[1m  PID    CPU%%  MEM(MB)  STATE    COMMAND\033[0m\n"
fmt_proc_run:   .asciz "\033[32m%5d  %3d.%d  %5d.%d  %-7s  %s\033[0m\n"
fmt_proc_norm:  .asciz "%5d  %3d.%d  %5d.%d  %-7s  %s\n"
fmt_proc_oth:   .asciz "\033[33m%5d  %3d.%d  %5d.%d  %-7s  %s\033[0m\n"
str_hw_memsize: .asciz "hw.memsize"
str_run:        .asciz "run"
str_sleep:      .asciz "sleep"
str_stop:       .asciz "stop"
str_zombie:     .asciz "zombie"
str_idle:       .asciz "idle"
str_unknown:    .asciz "???"

// ============================================================
// Small mutable data (__DATA,__data)
// ============================================================
.section __DATA,__data
.align 3

host_port:          .word 0
                    .word 0
total_memory:       .quad 0
cpu_ticks_old:      .space 16, 0
cpu_ticks_new:      .space 16, 0
cpu_user_pct:       .word 0
cpu_sys_pct:        .word 0
cpu_idle_pct:       .word 0
                    .word 0
mem_used_mb:        .quad 0
mem_free_mb:        .quad 0
pid_count:          .word 0
proc_total:         .word 0
proc_running:       .word 0
proc_sleeping:      .word 0
timebase_numer:     .word 0
timebase_denom:     .word 0
sort_count:         .word 0
prev_cpu_count:     .word 0
iteration:          .word 0

// ============================================================
// Large buffers (BSS — zero-filled, no binary bloat)
// ============================================================
.zerofill __DATA,__bss,_pid_buf,8192,4
.zerofill __DATA,__bss,_taskallinfo,232,4
.zerofill __DATA,__bss,_vm_stats,160,4
.zerofill __DATA,__bss,_sort_buf,98304,4
.zerofill __DATA,__bss,_prev_cpu,32768,4

// ============================================================
// Text section
// ============================================================
.section __TEXT,__text

// ============================================================
// _main
//   Frame: 32 bytes (x29/x30 at +16, 16 bytes scratch at +0)
// ============================================================
_main:
    sub     sp, sp, #32
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    // Get mach host port
    bl      _mach_host_self
    adrp    x1, host_port@PAGE
    add     x1, x1, host_port@PAGEOFF
    str     w0, [x1]

    // Get total memory
    bl      get_total_memory

    // Get mach timebase info
    sub     sp, sp, #16
    mov     x0, sp
    bl      _mach_timebase_info
    ldr     w1, [sp, #0]
    ldr     w2, [sp, #4]
    adrp    x3, timebase_numer@PAGE
    add     x3, x3, timebase_numer@PAGEOFF
    str     w1, [x3]
    adrp    x3, timebase_denom@PAGE
    add     x3, x3, timebase_denom@PAGEOFF
    str     w2, [x3]
    add     sp, sp, #16

    // Initial CPU snapshot + baseline process CPU times
    bl      get_cpu_ticks
    adrp    x0, cpu_ticks_new@PAGE
    add     x0, x0, cpu_ticks_new@PAGEOFF
    adrp    x1, cpu_ticks_old@PAGE
    add     x1, x1, cpu_ticks_old@PAGEOFF
    ldp     x2, x3, [x0]
    stp     x2, x3, [x1]

    // Gather baseline process CPU times (results discarded, but prev_cpu populated)
    bl      get_process_list
    bl      gather_process_info

main_loop:
    // Sleep 2 seconds (usleep is non-variadic: arg in w0)
    mov     w0, #0x8480
    movk    w0, #0x1E, lsl #16
    bl      _usleep

    // Copy new -> old ticks
    adrp    x0, cpu_ticks_new@PAGE
    add     x0, x0, cpu_ticks_new@PAGEOFF
    adrp    x1, cpu_ticks_old@PAGE
    add     x1, x1, cpu_ticks_old@PAGEOFF
    ldp     x2, x3, [x0]
    stp     x2, x3, [x1]

    // Gather system + process data
    bl      get_cpu_ticks
    bl      calc_cpu_pcts
    bl      get_vm_stats
    bl      calc_mem
    bl      get_process_list
    bl      gather_process_info
    bl      sort_by_cpu

    // Clear screen then print
    adrp    x0, fmt_clear@PAGE
    add     x0, x0, fmt_clear@PAGEOFF
    bl      _printf

    bl      print_summary
    bl      print_header
    bl      print_processes

    // Flush stdout
    mov     x0, #0
    bl      _fflush

    b       main_loop

// ============================================================
// get_total_memory (non-variadic calls only)
// ============================================================
get_total_memory:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x0, #8
    str     x0, [sp, #24]

    adrp    x0, str_hw_memsize@PAGE
    add     x0, x0, str_hw_memsize@PAGEOFF
    add     x1, sp, #16
    add     x2, sp, #24
    mov     x3, #0
    mov     x4, #0
    bl      _sysctlbyname

    ldr     x1, [sp, #16]
    adrp    x2, total_memory@PAGE
    add     x2, x2, total_memory@PAGEOFF
    str     x1, [x2]

    ldp     x29, x30, [sp], #32
    ret

// ============================================================
// get_cpu_ticks (non-variadic)
// ============================================================
get_cpu_ticks:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     w0, HOST_CPU_LOAD_INFO_COUNT
    str     w0, [sp, #16]

    adrp    x0, host_port@PAGE
    add     x0, x0, host_port@PAGEOFF
    ldr     w0, [x0]
    mov     w1, HOST_CPU_LOAD_INFO
    adrp    x2, cpu_ticks_new@PAGE
    add     x2, x2, cpu_ticks_new@PAGEOFF
    add     x3, sp, #16
    bl      _host_statistics

    ldp     x29, x30, [sp], #32
    ret

// ============================================================
// calc_cpu_pcts (leaf function)
// ============================================================
calc_cpu_pcts:
    adrp    x0, cpu_ticks_new@PAGE
    add     x0, x0, cpu_ticks_new@PAGEOFF
    adrp    x1, cpu_ticks_old@PAGE
    add     x1, x1, cpu_ticks_old@PAGEOFF

    ldr     w2, [x0, #CPU_USER]
    ldr     w3, [x0, #CPU_SYS]
    ldr     w4, [x0, #CPU_IDLE]
    ldr     w5, [x0, #CPU_NICE]
    ldr     w6, [x1, #CPU_USER]
    ldr     w7, [x1, #CPU_SYS]
    ldr     w8, [x1, #CPU_IDLE]
    ldr     w9, [x1, #CPU_NICE]

    sub     w2, w2, w6
    sub     w3, w3, w7
    sub     w4, w4, w8
    sub     w5, w5, w9
    add     w2, w2, w5              // user includes nice

    add     w10, w2, w3
    add     w10, w10, w4

    cmp     w10, #0
    b.eq    cpu_zero

    mov     w11, #1000
    umull   x12, w2, w11
    udiv    w12, w12, w10

    umull   x14, w3, w11
    udiv    w14, w14, w10

    mov     w15, #1000
    sub     w15, w15, w12
    sub     w15, w15, w14
    cmp     w15, #0
    csel    w15, wzr, w15, lt

    adrp    x0, cpu_user_pct@PAGE
    add     x0, x0, cpu_user_pct@PAGEOFF
    str     w12, [x0]
    str     w14, [x0, #4]
    str     w15, [x0, #8]
    ret

cpu_zero:
    adrp    x0, cpu_user_pct@PAGE
    add     x0, x0, cpu_user_pct@PAGEOFF
    str     wzr, [x0]
    str     wzr, [x0, #4]
    mov     w1, #1000
    str     w1, [x0, #8]
    ret

// ============================================================
// get_vm_stats (non-variadic)
// ============================================================
get_vm_stats:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     w0, HOST_VM_INFO64_COUNT
    str     w0, [sp, #16]

    adrp    x0, host_port@PAGE
    add     x0, x0, host_port@PAGEOFF
    ldr     w0, [x0]
    mov     w1, HOST_VM_INFO64
    adrp    x2, _vm_stats@PAGE
    add     x2, x2, _vm_stats@PAGEOFF
    add     x3, sp, #16
    bl      _host_statistics64

    ldp     x29, x30, [sp], #32
    ret

// ============================================================
// calc_mem (leaf)
// ============================================================
calc_mem:
    adrp    x0, _vm_stats@PAGE
    add     x0, x0, _vm_stats@PAGEOFF

    ldr     w1, [x0, #VM_FREE]
    ldr     w2, [x0, #VM_ACTIVE]
    ldr     w3, [x0, #VM_INACTIVE]
    ldr     w4, [x0, #VM_WIRE]
    ldr     w5, [x0, #VM_SPECULATIVE]
    ldr     w6, [x0, #VM_COMPRESSOR]

    mov     x10, x2
    add     x10, x10, x4
    add     x10, x10, x6
    lsr     x10, x10, #6           // pages/64 = MB (16KB pages)

    mov     x11, x1
    add     x11, x11, x3
    add     x11, x11, x5
    lsr     x11, x11, #6

    adrp    x0, mem_used_mb@PAGE
    add     x0, x0, mem_used_mb@PAGEOFF
    str     x10, [x0]
    adrp    x0, mem_free_mb@PAGE
    add     x0, x0, mem_free_mb@PAGEOFF
    str     x11, [x0]
    ret

// ============================================================
// get_process_list (non-variadic)
// ============================================================
get_process_list:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, _pid_buf@PAGE
    add     x0, x0, _pid_buf@PAGEOFF
    mov     x1, #8192
    bl      _proc_listallpids

    cmp     w0, #0
    b.le    gpl_zero
    asr     w0, w0, #2
    b       gpl_store
gpl_zero:
    mov     w0, #0
gpl_store:
    adrp    x1, pid_count@PAGE
    add     x1, x1, pid_count@PAGEOFF
    str     w0, [x1]

    ldp     x29, x30, [sp], #16
    ret

// ============================================================
// gather_process_info
// ============================================================
gather_process_info:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    // Zero counters
    adrp    x0, proc_total@PAGE
    add     x0, x0, proc_total@PAGEOFF
    str     wzr, [x0]
    str     wzr, [x0, #4]
    str     wzr, [x0, #8]
    adrp    x0, sort_count@PAGE
    add     x0, x0, sort_count@PAGEOFF
    str     wzr, [x0]

    adrp    x19, _pid_buf@PAGE
    add     x19, x19, _pid_buf@PAGEOFF
    adrp    x0, pid_count@PAGE
    add     x0, x0, pid_count@PAGEOFF
    ldr     w20, [x0]
    mov     w0, MAX_PIDS
    cmp     w20, w0
    csel    w20, w0, w20, hi
    mov     w21, #0

    adrp    x22, _sort_buf@PAGE
    add     x22, x22, _sort_buf@PAGEOFF
    adrp    x23, sort_count@PAGE
    add     x23, x23, sort_count@PAGEOFF
    adrp    x24, _taskallinfo@PAGE
    add     x24, x24, _taskallinfo@PAGEOFF

gpi_loop:
    cmp     w21, w20
    b.ge    gpi_done

    ldr     w25, [x19, x21, lsl #2]
    cmp     w25, #0
    b.eq    gpi_next

    // Zero taskallinfo (232 bytes)
    stp     xzr, xzr, [x24, #0]
    stp     xzr, xzr, [x24, #16]
    stp     xzr, xzr, [x24, #32]
    stp     xzr, xzr, [x24, #48]
    stp     xzr, xzr, [x24, #64]
    stp     xzr, xzr, [x24, #80]
    stp     xzr, xzr, [x24, #96]
    stp     xzr, xzr, [x24, #112]
    stp     xzr, xzr, [x24, #128]
    stp     xzr, xzr, [x24, #144]
    stp     xzr, xzr, [x24, #160]
    stp     xzr, xzr, [x24, #176]
    stp     xzr, xzr, [x24, #192]
    stp     xzr, xzr, [x24, #208]
    str     xzr, [x24, #224]

    // proc_pidinfo (non-variadic: x0-x4)
    mov     w0, w25
    mov     w1, PROC_PIDTASKALLINFO
    mov     x2, #0
    mov     x3, x24
    mov     w4, PROC_PIDTASKALLINFO_SIZE
    bl      _proc_pidinfo

    cmp     w0, PROC_PIDTASKALLINFO_SIZE
    b.lt    gpi_next

    // Count states using pti_numrunning (0 = sleeping, >0 = running)
    ldr     w0, [x24, #PTINFO_OFFSET + PTI_NUMRUNNING]
    adrp    x1, proc_total@PAGE
    add     x1, x1, proc_total@PAGEOFF
    ldr     w2, [x1]
    add     w2, w2, #1
    str     w2, [x1]

    cmp     w0, #0
    b.eq    1f
    // Running
    ldr     w2, [x1, #4]
    add     w2, w2, #1
    str     w2, [x1, #4]
    b       2f
1:
    // Sleeping
    ldr     w2, [x1, #8]
    add     w2, w2, #1
    str     w2, [x1, #8]
2:

    // Per-process CPU time
    ldr     x26, [x24, #PTINFO_OFFSET + PTI_TOTAL_USER]
    ldr     x27, [x24, #PTINFO_OFFSET + PTI_TOTAL_SYS]
    add     x26, x26, x27

    mov     w0, w25
    bl      lookup_prev_cpu
    mov     x27, x0

    mov     w0, w25
    mov     x1, x26
    bl      store_prev_cpu

    sub     x26, x26, x27

    adrp    x0, timebase_numer@PAGE
    add     x0, x0, timebase_numer@PAGEOFF
    ldr     w0, [x0]
    adrp    x1, timebase_denom@PAGE
    add     x1, x1, timebase_denom@PAGEOFF
    ldr     w1, [x1]
    cmp     w1, #0
    b.eq    gpi_zero_cpu

    mul     x26, x26, x0
    udiv    x26, x26, x1

    mov     x0, #0x8480
    movk    x0, #0x1E, lsl #16
    udiv    x28, x26, x0

    mov     x0, #9999
    cmp     x28, x0
    csel    x28, x0, x28, hi
    b       gpi_have_cpu

gpi_zero_cpu:
    mov     x28, #0
gpi_have_cpu:

    // Resident memory MB x10
    ldr     x26, [x24, #PTINFO_OFFSET + PTI_RESIDENT]
    mov     x0, #10
    mul     x26, x26, x0
    lsr     x26, x26, #20

    // Build sort entry
    ldr     w0, [x23]
    cmp     w0, MAX_PIDS
    b.ge    gpi_next

    mov     w1, SORT_ENTRY
    umull   x1, w0, w1
    add     x2, x22, x1

    str     w25, [x2, #SORT_PID]
    str     w28, [x2, #SORT_CPU]
    str     w26, [x2, #SORT_MEM]
    // Store state: use pti_numrunning > 0 → SRUN(2), else SSLEEP(3)
    ldr     w3, [x24, #PTINFO_OFFSET + PTI_NUMRUNNING]
    cmp     w3, #0
    mov     w4, #SRUN
    mov     w3, #SSLEEP
    csel    w3, w4, w3, ne         // SRUN if numrunning>0, else SSLEEP
    str     w3, [x2, #SORT_STATUS]

    add     x3, x24, #PBI_NAME
    ldrb    w4, [x3]
    cbnz    w4, gpi_copy
    add     x3, x24, #PBI_COMM
gpi_copy:
    add     x4, x2, #SORT_NAME
    mov     w5, #31
gpi_cloop:
    ldrb    w6, [x3], #1
    strb    w6, [x4], #1
    cbz     w6, gpi_cdone
    subs    w5, w5, #1
    b.ne    gpi_cloop
    strb    wzr, [x4]
gpi_cdone:

    ldr     w0, [x23]
    add     w0, w0, #1
    str     w0, [x23]

gpi_next:
    add     w21, w21, #1
    b       gpi_loop

gpi_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #96
    ret

// ============================================================
// lookup_prev_cpu: w0=pid → x0=prev_time (leaf)
// ============================================================
lookup_prev_cpu:
    adrp    x2, _prev_cpu@PAGE
    add     x2, x2, _prev_cpu@PAGEOFF
    adrp    x3, prev_cpu_count@PAGE
    add     x3, x3, prev_cpu_count@PAGEOFF
    ldr     w3, [x3]
    mov     w4, #0
lkp_loop:
    cmp     w4, w3
    b.ge    lkp_nf
    lsl     x5, x4, #4
    add     x6, x2, x5
    ldr     w7, [x6, #PREV_PID]
    cmp     w7, w0
    b.eq    lkp_found
    add     w4, w4, #1
    b       lkp_loop
lkp_found:
    ldr     x0, [x6, #PREV_CPUTIME]
    ret
lkp_nf:
    mov     x0, #0
    ret

// ============================================================
// store_prev_cpu: w0=pid, x1=time (leaf)
// ============================================================
store_prev_cpu:
    adrp    x2, _prev_cpu@PAGE
    add     x2, x2, _prev_cpu@PAGEOFF
    adrp    x3, prev_cpu_count@PAGE
    add     x3, x3, prev_cpu_count@PAGEOFF
    ldr     w4, [x3]
    mov     w5, #0
spc_loop:
    cmp     w5, w4
    b.ge    spc_new
    lsl     x6, x5, #4
    add     x7, x2, x6
    ldr     w8, [x7, #PREV_PID]
    cmp     w8, w0
    b.eq    spc_upd
    add     w5, w5, #1
    b       spc_loop
spc_upd:
    str     x1, [x7, #PREV_CPUTIME]
    ret
spc_new:
    cmp     w4, MAX_PREV
    b.ge    spc_ret
    lsl     x6, x4, #4
    add     x7, x2, x6
    str     w0, [x7, #PREV_PID]
    str     x1, [x7, #PREV_CPUTIME]
    add     w4, w4, #1
    str     w4, [x3]
spc_ret:
    ret

// ============================================================
// sort_by_cpu: Insertion sort descending
// ============================================================
sort_by_cpu:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    adrp    x19, _sort_buf@PAGE
    add     x19, x19, _sort_buf@PAGEOFF
    adrp    x0, sort_count@PAGE
    add     x0, x0, sort_count@PAGEOFF
    ldr     w20, [x0]

    mov     w21, #1
sort_outer:
    cmp     w21, w20
    b.ge    sort_done

    mov     w0, SORT_ENTRY
    umull   x0, w21, w0
    add     x1, x19, x0
    ldr     w22, [x1, #SORT_CPU]

    mov     w23, w21
sort_inner:
    cmp     w23, #0
    b.le    sort_next

    sub     w24, w23, #1
    mov     w0, SORT_ENTRY
    umull   x0, w24, w0
    add     x1, x19, x0
    ldr     w2, [x1, #SORT_CPU]
    cmp     w2, w22
    b.ge    sort_next

    // Swap 48 bytes: unrolled 6x8
    mov     w0, SORT_ENTRY
    umull   x3, w23, w0
    add     x3, x19, x3

    ldr     x5, [x1, #0]
    ldr     x6, [x3, #0]
    str     x6, [x1, #0]
    str     x5, [x3, #0]
    ldr     x5, [x1, #8]
    ldr     x6, [x3, #8]
    str     x6, [x1, #8]
    str     x5, [x3, #8]
    ldr     x5, [x1, #16]
    ldr     x6, [x3, #16]
    str     x6, [x1, #16]
    str     x5, [x3, #16]
    ldr     x5, [x1, #24]
    ldr     x6, [x3, #24]
    str     x6, [x1, #24]
    str     x5, [x3, #24]
    ldr     x5, [x1, #32]
    ldr     x6, [x3, #32]
    str     x6, [x1, #32]
    str     x5, [x3, #32]
    ldr     x5, [x1, #40]
    ldr     x6, [x3, #40]
    str     x6, [x1, #40]
    str     x5, [x3, #40]

    sub     w23, w23, #1
    b       sort_inner

sort_next:
    add     w21, w21, #1
    b       sort_outer

sort_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

// ============================================================
// print_summary
//   Frame: 64 bytes
//     [sp+48]: x29, x30
//     [sp+0..47]: printf variadic args (up to 6 args)
// ============================================================
print_summary:
    sub     sp, sp, #64
    stp     x29, x30, [sp, #48]
    add     x29, sp, #48

    // --- Processes line: printf(fmt, total, running, sleeping) ---
    // 3 variadic args on stack
    adrp    x8, proc_total@PAGE
    add     x8, x8, proc_total@PAGEOFF
    ldr     w1, [x8]               // total
    ldr     w2, [x8, #4]           // running
    ldr     w3, [x8, #8]           // sleeping
    str     x1, [sp, #0]           // variadic arg 1
    str     x2, [sp, #8]           // variadic arg 2
    str     x3, [sp, #16]          // variadic arg 3

    adrp    x0, fmt_procs@PAGE
    add     x0, x0, fmt_procs@PAGEOFF
    bl      _printf

    // --- CPU line: printf(fmt, u_int, u_frac, s_int, s_frac, i_int, i_frac) ---
    // 6 variadic args on stack
    adrp    x8, cpu_user_pct@PAGE
    add     x8, x8, cpu_user_pct@PAGEOFF
    ldr     w10, [x8]              // user x10
    ldr     w11, [x8, #4]          // sys x10
    ldr     w12, [x8, #8]          // idle x10

    mov     w9, #10
    udiv    w1, w10, w9
    msub    w2, w1, w9, w10
    udiv    w3, w11, w9
    msub    w4, w3, w9, w11
    udiv    w5, w12, w9
    msub    w6, w5, w9, w12

    str     x1, [sp, #0]           // user int
    str     x2, [sp, #8]           // user frac
    str     x3, [sp, #16]          // sys int
    str     x4, [sp, #24]          // sys frac
    str     x5, [sp, #32]          // idle int
    str     x6, [sp, #40]          // idle frac

    adrp    x0, fmt_cpu@PAGE
    add     x0, x0, fmt_cpu@PAGEOFF
    bl      _printf

    // --- Memory line: printf(fmt, used_mb, free_mb) ---
    // 2 variadic args (uint64) on stack
    adrp    x1, mem_used_mb@PAGE
    add     x1, x1, mem_used_mb@PAGEOFF
    ldr     x1, [x1]
    adrp    x2, mem_free_mb@PAGE
    add     x2, x2, mem_free_mb@PAGEOFF
    ldr     x2, [x2]
    str     x1, [sp, #0]
    str     x2, [sp, #8]

    adrp    x0, fmt_mem@PAGE
    add     x0, x0, fmt_mem@PAGEOFF
    bl      _printf

    ldp     x29, x30, [sp, #48]
    add     sp, sp, #64
    ret

// ============================================================
// print_header (no variadic args needed)
// ============================================================
print_header:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, fmt_header@PAGE
    add     x0, x0, fmt_header@PAGEOFF
    bl      _printf

    ldp     x29, x30, [sp], #16
    ret

// ============================================================
// print_processes
//   Frame: 144 bytes
//     [sp+128]: x29, x30
//     [sp+112]: x25, x26
//     [sp+96]:  x23, x24
//     [sp+80]:  x21, x22
//     [sp+64]:  x19, x20
//     [sp+0..55]: printf variadic args (7 args)
// ============================================================
print_processes:
    sub     sp, sp, #144
    stp     x29, x30, [sp, #128]
    add     x29, sp, #128
    stp     x19, x20, [sp, #64]
    stp     x21, x22, [sp, #80]
    stp     x23, x24, [sp, #96]
    stp     x25, x26, [sp, #112]

    adrp    x19, _sort_buf@PAGE
    add     x19, x19, _sort_buf@PAGEOFF
    adrp    x0, sort_count@PAGE
    add     x0, x0, sort_count@PAGEOFF
    ldr     w20, [x0]

    mov     w0, MAX_DISPLAY
    cmp     w20, w0
    csel    w20, w0, w20, hi

    mov     w21, #0
pp_loop:
    cmp     w21, w20
    b.ge    pp_done

    mov     w0, SORT_ENTRY
    umull   x0, w21, w0
    add     x22, x19, x0           // &entry[i] (callee-saved)

    // Pre-load into callee-saved regs
    ldr     w23, [x22, #SORT_PID]
    ldr     w24, [x22, #SORT_CPU]
    ldr     w25, [x22, #SORT_MEM]
    ldr     w26, [x22, #SORT_STATUS]

    // Get state string (leaf fn — won't clobber callee-saved)
    mov     w0, w26
    bl      get_state_str
    // x0 = state string pointer

    // Compute integer/frac for CPU and MEM
    mov     w9, #10
    udiv    w2, w24, w9            // cpu int
    msub    w3, w2, w9, w24        // cpu frac
    udiv    w4, w25, w9            // mem int
    msub    w5, w4, w9, w25        // mem frac

    // Store variadic args on stack [sp+0..55]
    str     x23, [sp, #0]          // pid
    str     x2,  [sp, #8]          // cpu int
    str     x3,  [sp, #16]         // cpu frac
    str     x4,  [sp, #24]         // mem int
    str     x5,  [sp, #32]         // mem frac
    str     x0,  [sp, #40]         // state string ptr
    add     x8, x22, #SORT_NAME
    str     x8,  [sp, #48]         // name string ptr

    // Choose format based on status
    cmp     w26, #SRUN
    b.eq    pp_run
    cmp     w26, #SSLEEP
    b.eq    pp_norm
    adrp    x0, fmt_proc_oth@PAGE
    add     x0, x0, fmt_proc_oth@PAGEOFF
    b       pp_call
pp_run:
    adrp    x0, fmt_proc_run@PAGE
    add     x0, x0, fmt_proc_run@PAGEOFF
    b       pp_call
pp_norm:
    adrp    x0, fmt_proc_norm@PAGE
    add     x0, x0, fmt_proc_norm@PAGEOFF

pp_call:
    bl      _printf

    add     w21, w21, #1
    b       pp_loop

pp_done:
    ldp     x19, x20, [sp, #64]
    ldp     x21, x22, [sp, #80]
    ldp     x23, x24, [sp, #96]
    ldp     x25, x26, [sp, #112]
    ldp     x29, x30, [sp, #128]
    add     sp, sp, #144
    ret

// ============================================================
// get_state_str: w0=status → x0=string ptr (leaf)
// ============================================================
get_state_str:
    cmp     w0, #SRUN
    b.eq    gs_run
    cmp     w0, #SSLEEP
    b.eq    gs_sleep
    cmp     w0, #SSTOP
    b.eq    gs_stop
    cmp     w0, #SZOMB
    b.eq    gs_zombie
    cmp     w0, #SIDL
    b.eq    gs_idle
    adrp    x0, str_unknown@PAGE
    add     x0, x0, str_unknown@PAGEOFF
    ret
gs_run:
    adrp    x0, str_run@PAGE
    add     x0, x0, str_run@PAGEOFF
    ret
gs_sleep:
    adrp    x0, str_sleep@PAGE
    add     x0, x0, str_sleep@PAGEOFF
    ret
gs_stop:
    adrp    x0, str_stop@PAGE
    add     x0, x0, str_stop@PAGEOFF
    ret
gs_zombie:
    adrp    x0, str_zombie@PAGE
    add     x0, x0, str_zombie@PAGEOFF
    ret
gs_idle:
    adrp    x0, str_idle@PAGE
    add     x0, x0, str_idle@PAGEOFF
    ret
