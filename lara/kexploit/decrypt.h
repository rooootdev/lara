//
//  decrypt.h
//  lara
//
//  Created by neonmodder123 on 23.05.26.
//

#ifndef decrypt_h
#define decrypt_h

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

typedef void (*log_callback_t)(const char *message);
typedef void (*progress_callback_t)(double progress);

void set_log_callback(log_callback_t callback);
void set_progress_callback(progress_callback_t callback);

extern volatile double decrypt_progress;

int is_encrypted(const char *bundlePath, const char *executableName);
int is_encrypted_path(const char *binaryPath);
int decrypt_app(const char *bundlePath, const char *executableName, const char *outputPath);
int decrypt_binary(const char *binaryPath, const char *processName, const char *outputPath);
int decrypt_binary_pid(const char *binaryPath, pid_t pid, const char *outputPath);

pid_t find_process_pid(const char *processName);
int launch_app(const char *bundleID);

#endif /* decrypt_h */
