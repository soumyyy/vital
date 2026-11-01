#ifndef CVITALSENSORS_H
#define CVITALSENSORS_H
#include <stdint.h>

// --- SMC (fans) ---------------------------------------------------------
// Opens the AppleSMC connection if needed. Returns 0 on success.
int vs_smc_open(void);
void vs_smc_close(void);
// Reads a 4-character key. On success returns 0 and fills type (4 chars, NUL-terminated),
// size and up to 32 bytes. Non-zero on failure (key missing, SMC unavailable).
int vs_smc_read(const char *key, char type_out[5], uint32_t *size_out, uint8_t bytes_out[32]);

// --- HID temperature sensors (Apple Silicon) ----------------------------
#define VS_MAX_SENSORS 96
#define VS_NAME_LEN 64
// names is a flat buffer of VS_MAX_SENSORS * VS_NAME_LEN chars; entry i starts at names + i * VS_NAME_LEN.
// Returns the number of sensors read (0 if none/unavailable).
int vs_hid_temperatures(char *names, double *values);
#endif
