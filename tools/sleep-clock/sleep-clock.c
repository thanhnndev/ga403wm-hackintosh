// Prints mach_absolute_time, mach_continuous_time and their difference (time the kernel counted as asleep since boot).
// Build: cc -O -o /tmp/sleep-clock tools/sleep-clock/sleep-clock.c. Run before and after a sleep; see docs/BOOT-TIMELINE.md 0.1.

#include <stdio.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <time.h>
int main(){ mach_timebase_info_data_t tb; mach_timebase_info(&tb);
 unsigned long long a=mach_absolute_time(), c=mach_continuous_time();
 struct timeval bt; size_t l=sizeof bt; sysctlbyname("kern.boottime",&bt,&l,0,0);
 double as=(double)a*tb.numer/tb.denom/1e9, cs=(double)c*tb.numer/tb.denom/1e9;
 printf("absolute %.1f s  continuous %.1f s  slept(cont-abs) %.1f s  wall since boottime %ld s\n", as, cs, cs-as, (long)(time(0)-bt.tv_sec)); }
