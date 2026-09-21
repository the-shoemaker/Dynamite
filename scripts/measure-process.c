// Read-only per-process counters. No task-port access, sampling stacks, or UI reads.
// CPU % is relative to one logical core; memory values are bytes converted to MiB.
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static int read_usage(int pid, struct rusage_info_v4 *r) {
    memset(r, 0, sizeof(*r));
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)r)) { perror("proc_pid_rusage"); return 0; }
    return 1;
}
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "Usage: %s PID samples interval_seconds\n", argv[0]); return 2; }
    int pid = atoi(argv[1]), samples = atoi(argv[2]), interval = atoi(argv[3]);
    if (pid <= 0 || samples < 1 || samples > 360 || interval < 1 || interval > 60) return 2;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    const double tick_seconds = (double)timebase.numer / timebase.denom / 1e9;
    struct rusage_info_v4 first, previous, current;
    if (!read_usage(pid, &first)) return 1;
    previous = first;
    double start = now(), last = start;
    setvbuf(stdout, NULL, _IOLBF, 0);
    printf("{\"pid\":%d,\"initial_footprint_mib\":%.3f,\"initial_resident_mib\":%.3f}\n", pid, first.ri_phys_footprint / 1048576.0, first.ri_resident_size / 1048576.0);
    for (int i = 0; i < samples; ++i) {
        sleep(interval);
        if (!read_usage(pid, &current)) return 1;
        if (memcmp(current.ri_uuid, first.ri_uuid, 16) || current.ri_proc_start_abstime != first.ri_proc_start_abstime) { fprintf(stderr, "Process changed during measurement\n"); return 1; }
        double t = now(), elapsed = t - last;
        printf("{\"elapsed_s\":%.3f,\"cpu_percent\":%.4f,\"interrupt_wakeups_s\":%.3f,\"package_idle_wakeups_s\":%.3f,\"footprint_mib\":%.3f,\"resident_mib\":%.3f,\"disk_read_bytes\":%llu,\"disk_write_bytes\":%llu}\n", t - start,
            (current.ri_user_time - previous.ri_user_time + current.ri_system_time - previous.ri_system_time) * tick_seconds / elapsed * 100,
            (current.ri_interrupt_wkups - previous.ri_interrupt_wkups) / elapsed,
            (current.ri_pkg_idle_wkups - previous.ri_pkg_idle_wkups) / elapsed,
            current.ri_phys_footprint / 1048576.0, current.ri_resident_size / 1048576.0,
            (unsigned long long)(current.ri_diskio_bytesread - previous.ri_diskio_bytesread),
            (unsigned long long)(current.ri_diskio_byteswritten - previous.ri_diskio_byteswritten));
        previous = current; last = t;
    }
    printf("{\"summary\":true,\"duration_s\":%.3f,\"cpu_percent\":%.4f,\"interrupt_wakeups_s\":%.3f,\"package_idle_wakeups_s\":%.3f,\"footprint_delta_mib\":%.3f}\n", last - start,
        (current.ri_user_time - first.ri_user_time + current.ri_system_time - first.ri_system_time) * tick_seconds / (last - start) * 100,
        (current.ri_interrupt_wkups - first.ri_interrupt_wkups) / (last - start),
        (current.ri_pkg_idle_wkups - first.ri_pkg_idle_wkups) / (last - start),
        ((double)current.ri_phys_footprint - first.ri_phys_footprint) / 1048576.0);
}
