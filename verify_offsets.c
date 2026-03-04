/*
 * verify_offsets.c — Print struct sizes and field offsets
 * used by top.s to access kernel/Mach data structures.
 *
 * Build: cc -o verify_offsets verify_offsets.c
 * Run:   ./verify_offsets
 */
#include <stdio.h>
#include <stddef.h>
#include <mach/mach.h>
#include <mach/host_info.h>
#include <mach/vm_statistics.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <libproc.h>

int main(void) {
    printf("=== Struct Sizes ===\n");
    printf("sizeof(host_cpu_load_info_data_t) = %zu\n", sizeof(host_cpu_load_info_data_t));
    printf("sizeof(vm_statistics64_data_t)    = %zu\n", sizeof(vm_statistics64_data_t));
    printf("sizeof(mach_timebase_info_data_t) = %zu\n", sizeof(mach_timebase_info_data_t));
    printf("sizeof(struct proc_taskallinfo)   = %zu\n", sizeof(struct proc_taskallinfo));
    printf("sizeof(struct proc_bsdinfo)       = %zu\n", sizeof(struct proc_bsdinfo));
    printf("sizeof(struct proc_taskinfo)      = %zu\n", sizeof(struct proc_taskinfo));

    printf("\n=== host_cpu_load_info_data_t ===\n");
    printf("  cpu_ticks[CPU_STATE_USER]   offset = %zu\n",
           offsetof(host_cpu_load_info_data_t, cpu_ticks[CPU_STATE_USER]));
    printf("  cpu_ticks[CPU_STATE_SYSTEM] offset = %zu\n",
           offsetof(host_cpu_load_info_data_t, cpu_ticks[CPU_STATE_SYSTEM]));
    printf("  cpu_ticks[CPU_STATE_IDLE]   offset = %zu\n",
           offsetof(host_cpu_load_info_data_t, cpu_ticks[CPU_STATE_IDLE]));
    printf("  cpu_ticks[CPU_STATE_NICE]   offset = %zu\n",
           offsetof(host_cpu_load_info_data_t, cpu_ticks[CPU_STATE_NICE]));
    printf("  CPU_STATE_USER=%d SYSTEM=%d IDLE=%d NICE=%d\n",
           CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE);
    printf("  CPU_STATE_MAX=%d\n", CPU_STATE_MAX);

    printf("\n=== vm_statistics64_data_t offsets ===\n");
    printf("  free_count     offset = %zu\n", offsetof(vm_statistics64_data_t, free_count));
    printf("  active_count   offset = %zu\n", offsetof(vm_statistics64_data_t, active_count));
    printf("  inactive_count offset = %zu\n", offsetof(vm_statistics64_data_t, inactive_count));
    printf("  wire_count     offset = %zu\n", offsetof(vm_statistics64_data_t, wire_count));
    printf("  speculative_count offset = %zu\n", offsetof(vm_statistics64_data_t, speculative_count));
    printf("  internal_page_count offset = %zu\n", offsetof(vm_statistics64_data_t, internal_page_count));
    printf("  external_page_count offset = %zu\n", offsetof(vm_statistics64_data_t, external_page_count));
    printf("  compressor_page_count offset = %zu\n", offsetof(vm_statistics64_data_t, compressor_page_count));

    printf("\n=== mach_timebase_info_data_t ===\n");
    printf("  numer offset = %zu\n", offsetof(mach_timebase_info_data_t, numer));
    printf("  denom offset = %zu\n", offsetof(mach_timebase_info_data_t, denom));

    printf("\n=== struct proc_taskallinfo ===\n");
    printf("  pbsd  offset = %zu, size = %zu\n",
           offsetof(struct proc_taskallinfo, pbsd),
           sizeof(((struct proc_taskallinfo *)0)->pbsd));
    printf("  ptinfo offset = %zu, size = %zu\n",
           offsetof(struct proc_taskallinfo, ptinfo),
           sizeof(((struct proc_taskallinfo *)0)->ptinfo));

    printf("\n=== struct proc_bsdinfo (inside taskallinfo.pbsd) ===\n");
    printf("  pbi_flags    offset = %zu\n", offsetof(struct proc_bsdinfo, pbi_flags));
    printf("  pbi_status   offset = %zu\n", offsetof(struct proc_bsdinfo, pbi_status));
    printf("  pbi_pid      offset = %zu\n", offsetof(struct proc_bsdinfo, pbi_pid));
    printf("  pbi_comm     offset = %zu (size %zu)\n",
           offsetof(struct proc_bsdinfo, pbi_comm),
           sizeof(((struct proc_bsdinfo *)0)->pbi_comm));
    printf("  pbi_name     offset = %zu (size %zu)\n",
           offsetof(struct proc_bsdinfo, pbi_name),
           sizeof(((struct proc_bsdinfo *)0)->pbi_name));

    printf("\n=== struct proc_taskinfo (inside taskallinfo.ptinfo) ===\n");
    printf("  pti_virtual_size   offset = %zu\n", offsetof(struct proc_taskinfo, pti_virtual_size));
    printf("  pti_resident_size  offset = %zu\n", offsetof(struct proc_taskinfo, pti_resident_size));
    printf("  pti_total_user     offset = %zu\n", offsetof(struct proc_taskinfo, pti_total_user));
    printf("  pti_total_system   offset = %zu\n", offsetof(struct proc_taskinfo, pti_total_system));
    printf("  pti_threads_user   offset = %zu\n", offsetof(struct proc_taskinfo, pti_threads_user));
    printf("  pti_threads_system offset = %zu\n", offsetof(struct proc_taskinfo, pti_threads_system));

    printf("\n=== Constants ===\n");
    printf("HOST_CPU_LOAD_INFO       = %d\n", HOST_CPU_LOAD_INFO);
    printf("HOST_CPU_LOAD_INFO_COUNT = %d\n", HOST_CPU_LOAD_INFO_COUNT);
    printf("HOST_VM_INFO64           = %d\n", HOST_VM_INFO64);
    printf("HOST_VM_INFO64_COUNT     = %d\n", HOST_VM_INFO64_COUNT);
    printf("PROC_PIDTASKALLINFO      = %d\n", PROC_PIDTASKALLINFO);
    printf("PROC_PIDTASKALLINFO_SIZE = %zu\n", sizeof(struct proc_taskallinfo));
    printf("vm_kernel_page_size      = %u\n", vm_kernel_page_size);

    printf("\n=== Status constants ===\n");
    printf("SRUN  = %d\n", SRUN);
    printf("SSLEEP = %d\n", SSLEEP);
    printf("SSTOP  = %d\n", SSTOP);
    printf("SZOMB  = %d\n", SZOMB);
    printf("SIDL   = %d\n", SIDL);

    return 0;
}
