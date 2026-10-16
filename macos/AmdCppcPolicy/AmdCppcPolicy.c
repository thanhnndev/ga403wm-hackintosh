// SPDX-License-Identifier: BSD-3-Clause-Clear
// HX 370 CPPC autonomous policy. Serialized on the CF run loop; root LaunchDaemon.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <spawn.h>
#include <signal.h>
extern char **environ;
static io_connect_t powerPort;
static int sleeping, lastEpp = -1, failures;
static int number(const char *key) { int v = -1; size_t n = sizeof(v); return sysctlbyname(key, &v, &n, NULL, 0) ? -1 : v; }
static int string(const char *key, char *buf, size_t cap) { size_t n = cap; memset(buf, 0, cap); return sysctlbyname(key, buf, &n, NULL, 0); }
static int writeInt(const char *key, int v) { return sysctlbyname(key, NULL, NULL, &v, sizeof(v)); }
static int preference(int ac, int profile) { return profile == 2 ? 255 : !ac ? 191 : profile == 1 ? 0 : 128; }
// Parse every report group and ensure its multiplicity covers all logical CPUs.
static int verify(const char *report, int epp, int requireEnabled) {
    char copy[32768]; snprintf(copy, sizeof(copy), "%s", report);
    int total = 0; char *save = NULL;
    for (char *part = strtok_r(copy, "|", &save); part; part = strtok_r(NULL, "|", &save)) {
        int cpu, count, boost, ctl, stat, p0, enabled, high, nom, nl, low, max, min, des, got;
        while (*part == ' ') part++;
        if (sscanf(part, "cpu%d(x%d): CpbDis=%d PStateCtl=%d PStateStat=%d P0=%dMHz", &cpu,&count,&boost,&ctl,&stat,&p0) != 6) return 0;
        const char *cp = strstr(part, "CPPC_EN="), *cap = strstr(part, "CAP1="), *req = strstr(part, "REQ=");
        if (!cp || !cap || !req || sscanf(cp, "CPPC_EN=%d", &enabled) != 1 ||
            sscanf(cap, "CAP1=high %d nom %d lownl %d low %d", &high,&nom,&nl,&low) != 4 ||
            sscanf(req, "REQ=max %d min %d des %d epp %d", &max,&min,&des,&got) != 4) return 0;
        if (cpu < 0 || cpu >= 24 || count < 1 || !low || low > nl || nl > nom || nom > high || high > 255 || p0 <= 0) return 0;
        if (requireEnabled && enabled != 1) return 0;
        if (epp >= 0 && (max != high || min != nl || des != 0 || got != epp)) return 0;
        total += count;
    }
    return total == number("hw.ncpu");
}
static int supported(void) {
    char brand[256];
    return number("machdep.cpu.family") == 26 && number("machdep.cpu.model") == 36 && number("hw.ncpu") == 24 &&
        !string("machdep.cpu.brand_string", brand, sizeof(brand)) && strstr(brand, "Ryzen AI 9 HX 370");
}
static int apply(int forced) {
    if (sleeping) return 0;
    char asus[4096], report[32768];
    if (!supported() || string("debug.amdcppc.report", report, sizeof(report)) || !verify(report,-1,0)) goto fail;
    int ac = 0, profile = 0;
    if (!string("debug.asuswmi.status", asus, sizeof(asus))) {
        ac = !strncmp(asus,"ac ",3);
        const char *p = strstr(asus,"set_profile="); if (p) sscanf(p,"set_profile=%d", &profile);
    }
    int epp = forced >= 0 ? forced : preference(ac, profile);
    // Verify even when unchanged: firmware may reset requests during a power transition.
    if (!verify(report,-1,1)) {
        if (writeInt("debug.amdcppc.cppc",1) || string("debug.amdcppc.report", report, sizeof(report)) || !verify(report,-1,1)) goto fail;
    }
    if (!verify(report,epp,1)) {
        if (writeInt("debug.amdcppc.epp",epp) || string("debug.amdcppc.report", report, sizeof(report)) || !verify(report,epp,1)) goto fail;
    }
    if (lastEpp != epp) { printf("policy: %s profile=%d EPP=%d verified on 24 CPUs\n",ac?"AC":"battery",profile,epp); fflush(stdout); }
    lastEpp = epp; failures = 0; return 0;
fail:
    fprintf(stderr,"policy: unavailable/readback failed (errno=%d); no legacy P-state or boost override\n",errno); fflush(stderr);
    failures++; return -1;
}
static void timer(CFRunLoopTimerRef unused, void *arg) { (void)unused; (void)arg; if (failures < 3) apply(-1); }
static void power(void *arg, io_service_t service, natural_t message, void *data) {
    (void)arg; (void)service;
    if (message == kIOMessageCanSystemSleep) IOAllowPowerChange(powerPort,(long)data);
    else if (message == kIOMessageSystemWillSleep) { sleeping = 1; IOAllowPowerChange(powerPort,(long)data); }
    else if (message == kIOMessageSystemHasPoweredOn || message == kIOMessageSystemWillNotSleep) {
        sleeping = 0; lastEpp = -1; failures = 0; // timer retries after devices settle, never writes in the notification callback
        puts("policy: wake; reapply scheduled"); fflush(stdout);
    }
}
static int snapshot(const char *label) {
    char buf[32768]; printf("\n[%s]\n",label);
    const char *keys[] = {"debug.amdcppc.report","debug.amdcppc.freq","debug.amdcppc.sensors"};
    for (unsigned i=0;i<3;i++) { if (string(keys[i],buf,sizeof(buf))) return -1; printf("%s: %s\n",keys[i],buf); }
    fflush(stdout); return 0;
}
static int load(int workers) {
    pid_t pids[24] = {0}; int result = 0;
    for (int i=0;i<workers;i++) {
        pid_t pid = fork();
        if (pid == -1) { result = -1; break; }
        if (!pid) { signal(SIGTERM,SIG_DFL); signal(SIGALRM,SIG_DFL); alarm(15); volatile unsigned long long x=1; for (;;) x=x*6364136223846793005ULL+1; }
        pids[i]=pid;
    }
    if (!result) { sleep(2); for (int i=0;i<4;i++) { if (snapshot(workers == 1 ? "single-worker" : "24-workers")) result=-1; sleep(1); } }
    for (int i=0;i<workers;i++) if (pids[i]) { kill(pids[i],SIGTERM); waitpid(pids[i],NULL,0); }
    return result;
}
static int test(void) {
    if (preference(1,0)!=128 || preference(1,1)!=0 || preference(1,2)!=255 || preference(0,0)!=191 || preference(0,1)!=191) return 1;
    if (snapshot("baseline") || apply(0) || snapshot("CPPC performance") || load(1) || load(24)) { apply(-1); return 1; }
    // Exercise the same notification state machine; this is not a physical sleep test.
    sleeping=1; if (apply(128)) return 1;
    power(NULL,0,kIOMessageSystemHasPoweredOn,NULL);
    if (apply(-1) || snapshot("wake-handler simulation, default policy restored")) return 1;
    puts("PASS: policy mapping, 24-CPU readback, idle/single/all-core collection, simulated wake. Physical sleep not tested.");
    return 0;
}
int main(int argc, char **argv) {
    if (geteuid()) { fputs("root required\n",stderr); return 1; }
    if (argc==2 && !strcmp(argv[1],"--test")) return test();
    if (argc==2 && !strcmp(argv[1],"--once")) return apply(-1) ? 1 : 0;
    IONotificationPortRef notify=NULL; io_object_t notifier=0;
    powerPort=IORegisterForSystemPower(NULL,&notify,power,&notifier);
    if (!powerPort || !notify) return 1;
    CFRunLoopAddSource(CFRunLoopGetCurrent(),IONotificationPortGetRunLoopSource(notify),kCFRunLoopDefaultMode);
    CFRunLoopTimerRef t=CFRunLoopTimerCreate(NULL,CFAbsoluteTimeGetCurrent()+2,5,0,0,timer,NULL);
    if (!t) return 1;
    CFRunLoopAddTimer(CFRunLoopGetCurrent(),t,kCFRunLoopDefaultMode);
    CFRunLoopRun();
    return 0;
}
