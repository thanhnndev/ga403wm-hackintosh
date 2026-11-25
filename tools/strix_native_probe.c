// SPDX-License-Identifier: BSD-3-Clause-Clear
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../include/StrixNativeABI.h"

int main(int argc, char **argv) {
    int foundation = argc == 2 && !strcmp(argv[1], "--foundation");
    if (argc != 1 && !foundation) { fprintf(stderr, "Usage: strix-native-probe [--foundation]\n"); return 2; }
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("StrixAccelerator"), &iterator);
    if (kr != KERN_SUCCESS) { fprintf(stderr, "Matching: 0x%x\n", kr); return 1; }
    io_service_t service = IOIteratorNext(iterator), extra = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!service || extra) {
        if (service) IOObjectRelease(service);
        if (extra) IOObjectRelease(extra);
        puts("{\"status\":\"ABSENT-or-ambiguous-StrixAccelerator\",\"metal_ready\":false}"); return 10;
    }
    CFTypeRef advertised = IORegistryEntryCreateCFProperty(service, CFSTR("StrixNative,ABIMajor"), kCFAllocatorDefault, 0);
    if (!advertised) {
        IOObjectRelease(service);
        puts("{\"status\":\"ABSENT-native-ABI-on-loaded-driver\",\"metal_ready\":false}"); return 10;
    }
    int major = 0;
    if (CFGetTypeID(advertised) == CFNumberGetTypeID()) CFNumberGetValue(advertised, kCFNumberIntType, &major);
    CFRelease(advertised);
    if (major != S89N_ABI_MAJOR) { IOObjectRelease(service); fprintf(stderr, "Unsupported advertised ABI\n"); return 1; }
    io_connect_t connection = IO_OBJECT_NULL;
    kr = IOServiceOpen(service, mach_task_self(), S89N_UC_TYPE, &connection); IOObjectRelease(service);
    if (kr != KERN_SUCCESS) { fprintf(stderr, "S89N open: 0x%x\n", kr); return 1; }
    int result = 1;
    s89n_info info; size_t size = sizeof(info);
    // Query before Hello must fail; no client can skip version negotiation.
    kr = IOConnectCallStructMethod(connection, S89N_QUERY_INFO, NULL, 0, &info, &size);
    if (kr != kIOReturnNotReady) { fprintf(stderr, "Pre-Hello query not rejected: 0x%x\n", kr); goto done; }
    s89n_hello_request request = {S89N_ABI_MAJOR, S89N_ABI_MINOR, {1, 0}};
    s89n_hello_reply reply; size = sizeof(reply);
    kr = IOConnectCallStructMethod(connection, S89N_HELLO, &request, sizeof(request), &reply, &size);
    if (kr != kIOReturnBadArgument) { fprintf(stderr, "Reserved input not rejected: 0x%x\n", kr); goto done; }
    request.reserved[0] = 0; request.major = S89N_ABI_MAJOR + 1; size = sizeof(reply);
    kr = IOConnectCallStructMethod(connection, S89N_HELLO, &request, sizeof(request), &reply, &size);
    if (kr != kIOReturnUnsupported) { fprintf(stderr, "Incompatible major not rejected: 0x%x\n", kr); goto done; }
    request.major = S89N_ABI_MAJOR; size = sizeof(reply);
    kr = IOConnectCallStructMethod(connection, S89N_HELLO, &request, sizeof(request) - 1, &reply, &size);
    if (kr == KERN_SUCCESS) { fprintf(stderr, "Short request accepted\n"); goto done; }
    size = sizeof(reply);
    kr = IOConnectCallStructMethod(connection, S89N_HELLO, &request, sizeof(request), &reply, &size);
    if (kr || size != sizeof(reply) || reply.magic != S89N_MAGIC || reply.major != S89N_ABI_MAJOR ||
        reply.minor > S89N_ABI_MINOR || reply.size != sizeof(reply) || reply.reserved) {
        fprintf(stderr, "Invalid Hello: 0x%x\n", kr); goto done;
    }
    memset(&info, 0x5a, sizeof(info)); size = sizeof(info);
    kr = IOConnectCallStructMethod(connection, S89N_QUERY_INFO, NULL, 0, &info, &size);
    if (kr || size != sizeof(info) || info.size != sizeof(info) || info.magic != S89N_MAGIC ||
        info.major != S89N_ABI_MAJOR || info.vendor_device != 0x150e1002 ||
        (info.revision_class & 255) != 0xc1 || info.subsystem != 0x39981043 || info.reserved0) {
        fprintf(stderr, "Invalid physical device info: 0x%x\n", kr); goto done;
    }
    for (unsigned i = 0; i < 7; ++i) if (info.reserved[i]) { fprintf(stderr, "Nonzero reserved output\n"); goto done; }
    if (!memchr(info.os_build, 0, sizeof(info.os_build))) { fprintf(stderr, "Unterminated build string\n"); goto done; }
    s89n_foundation registers = {0};
    unsigned negative_checks = 4;
    size_t unsupported_size = sizeof(registers);
    kr = IOConnectCallStructMethod(connection, S89N_SELECTOR_COUNT, NULL, 0, &registers, &unsupported_size);
    if (kr != kIOReturnUnsupported) { fprintf(stderr, "Unknown selector accepted: 0x%x\n", kr); goto done; }
    ++negative_checks;
    if (!foundation && geteuid() != 0 && (info.capabilities & S89N_CAP_FOUNDATION_READ)) {
        size = sizeof(registers);
        kr = IOConnectCallStructMethod(connection, S89N_FOUNDATION_READ, NULL, 0, &registers, &size);
        if (kr != kIOReturnNotPrivileged) { fprintf(stderr, "Admin-only MMIO read not denied: 0x%x\n", kr); goto done; }
        ++negative_checks;
    }
    if (foundation) {
        if (reply.minor < 1 || !(info.capabilities & S89N_CAP_FOUNDATION_READ)) {
            fprintf(stderr, "Foundation read not supported\n"); goto done;
        }
        size = sizeof(registers);
        kr = IOConnectCallStructMethod(connection, S89N_FOUNDATION_READ, NULL, 0, &registers, &size);
        if (kr || size != sizeof(registers) || registers.magic != S89N_MAGIC ||
            registers.size != sizeof(registers) || registers.reserved0 || registers.reserved) {
            fprintf(stderr, "Foundation read: 0x%x\n", kr); goto done;
        }
    }
    printf("{\"status\":\"PASS-native-query-contract\",\"abi\":\"%u.%u\",\"vendor_device\":\"0x%x\","
           "\"readiness\":%u,\"backend\":%u,\"capabilities\":%llu,\"expected_gc_ip\":%u,\"discovered_gc_ip\":%u,"
           "\"negative_checks_passed\":%u,\"metal_ready\":%s", info.major, info.minor, info.vendor_device,
           info.readiness, info.backend, (unsigned long long)info.capabilities, info.expected_gc_ip,
           info.discovered_gc_ip, negative_checks, s89n_metal_ready(&info) ? "true" : "false");
    if (foundation) printf(",\"foundation\":{\"rcc_memsize_mib\":%u,\"ip_discovery_version_raw\":%u,"
                           "\"psp_discovery_status_raw\":%u}", registers.rcc_memsize_mib,
                           registers.ip_discovery_version, registers.psp_discovery_status);
    puts("}");
    result = 0;
done:
    IOServiceClose(connection); return result;
}
