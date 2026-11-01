#include "cvitalsensors.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include <pthread.h>

// ---- SMC ----------------------------------------------------------------
typedef struct { char major, minor, build, reserved[1]; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key; SMCVersion vers; SMCPLimitData pLimitData; SMCKeyInfoData keyInfo;
    uint8_t result, status, data8; uint32_t data32; uint8_t bytes[32];
} SMCKeyData;

enum { kSMCUserClientOpen = 0, kSMCUserClientClose = 1, kSMCHandleYPCEvent = 2,
       kSMCReadKey = 5, kSMCGetKeyInfo = 9 };

static io_connect_t g_conn = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static int smc_open_locked(void) {
    if (g_conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { g_conn = 0; return -2; }
    return 0;
}

int vs_smc_open(void) {
    pthread_mutex_lock(&g_lock);
    int r = smc_open_locked();
    pthread_mutex_unlock(&g_lock);
    return r;
}

void vs_smc_close(void) {
    pthread_mutex_lock(&g_lock);
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
    pthread_mutex_unlock(&g_lock);
}

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static int smc_call(SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t kr = IOConnectCallStructMethod(g_conn, kSMCHandleYPCEvent, in, sizeof(SMCKeyData), out, &outSize);
    return (kr == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

int vs_smc_read(const char *key, char type_out[5], uint32_t *size_out, uint8_t bytes_out[32]) {
    if (!key || strlen(key) != 4) return -3;
    pthread_mutex_lock(&g_lock);
    int rc = smc_open_locked();
    if (rc != 0) { pthread_mutex_unlock(&g_lock); return rc; }
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(&in, &out) != 0) { pthread_mutex_unlock(&g_lock); return -4; }
    uint32_t size = out.keyInfo.dataSize;
    uint32_t type = out.keyInfo.dataType;
    if (size == 0 || size > 32) { pthread_mutex_unlock(&g_lock); return -5; }
    memset(&in, 0, sizeof in);
    in.key = fourcc(key);
    in.keyInfo.dataSize = size;
    in.data8 = kSMCReadKey;
    memset(&out, 0, sizeof out);
    if (smc_call(&in, &out) != 0) { pthread_mutex_unlock(&g_lock); return -6; }
    memcpy(bytes_out, out.bytes, size);
    *size_out = size;
    type_out[0] = (char)(type >> 24); type_out[1] = (char)(type >> 16);
    type_out[2] = (char)(type >> 8);  type_out[3] = (char)type; type_out[4] = 0;
    pthread_mutex_unlock(&g_lock);
    return 0;
}

// ---- HID temperature sensors (private IOKit API, same data powermetrics reads) ----
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t type, int32_t options, int64_t timeout);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef key);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventFieldTemperatureLevel (kIOHIDEventTypeTemperature << 16)

static IOHIDEventSystemClientRef g_hid = NULL;

int vs_hid_temperatures(char *names, double *values) {
    pthread_mutex_lock(&g_lock);
    if (!g_hid) {
        g_hid = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!g_hid) { pthread_mutex_unlock(&g_lock); return 0; }
        int page = 0xff00, usage = 5;
        CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *vals[] = { p, u };
        CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDEventSystemClientSetMatching(g_hid, match);
        CFRelease(match); CFRelease(p); CFRelease(u);
    }
    IOHIDEventSystemClientRef client = g_hid;
    pthread_mutex_unlock(&g_lock);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) return 0;
    int n = 0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count && n < VS_MAX_SENSORS; i++) {
        IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        CFTypeRef product = IOHIDServiceClientCopyProperty(svc, CFSTR("Product"));
        IOHIDEventRef ev = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0);
        if (ev) {
            double v = IOHIDEventGetFloatValue(ev, kIOHIDEventFieldTemperatureLevel);
            CFRelease(ev);
            char *slot = names + (size_t)n * VS_NAME_LEN;
            slot[0] = 0;
            if (product && CFGetTypeID(product) == CFStringGetTypeID())
                CFStringGetCString((CFStringRef)product, slot, VS_NAME_LEN, kCFStringEncodingUTF8);
            values[n] = v;
            n++;
        }
        if (product) CFRelease(product);
    }
    CFRelease(services);
    return n;
}

// ---- App responsiveness (private CoreGraphics API, resolved at runtime; missing symbols mean "unknown") ----
#include <dlfcn.h>
#include <ApplicationServices/ApplicationServices.h>
typedef int (*CGSMainConnectionIDFn)(void);
typedef bool (*CGSEventIsAppUnresponsiveFn)(int cid, const ProcessSerialNumber *psn);
typedef OSStatus (*GetProcessForPIDFn)(pid_t pid, ProcessSerialNumber *psn);

int vs_app_unresponsive(int pid) {
    static CGSMainConnectionIDFn mainConn;
    static CGSEventIsAppUnresponsiveFn isUnresponsive;
    static GetProcessForPIDFn getPSN;
    static int resolved = 0;
    if (!resolved) {
        mainConn = (CGSMainConnectionIDFn)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
        isUnresponsive = (CGSEventIsAppUnresponsiveFn)dlsym(RTLD_DEFAULT, "CGSEventIsAppUnresponsive");
        getPSN = (GetProcessForPIDFn)dlsym(RTLD_DEFAULT, "GetProcessForPID");
        resolved = 1;
    }
    if (!mainConn || !isUnresponsive || !getPSN) return -1;
    int cid = mainConn();
    if (cid == 0) return -1;
    ProcessSerialNumber psn;
    if (getPSN((pid_t)pid, &psn) != 0) return -1;
    return isUnresponsive(cid, &psn) ? 1 : 0;
}
