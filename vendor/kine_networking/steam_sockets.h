#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif


typedef struct KineGnsHost KineGnsHost;

typedef struct KineGnsEvent {
    int32_t type;
    uint32_t peer;
    uint8_t channel;
    uint8_t reserved[3];
    const uint8_t *data;
    uint32_t data_size;
} KineGnsEvent;

bool Kine_Gns_Init(void);
void Kine_Gns_Kill(void);
uint32_t Kine_Gns_TimeMs(void);


int32_t Kine_Gns_GetSendRate(KineGnsHost *host);
bool Kine_Gns_SetSendRate(KineGnsHost *host, int32_t bytes_per_second);

KineGnsHost *Kine_Gns_CreateServer(const char *address, uint16_t port, int32_t max_peers);
KineGnsHost *Kine_Gns_CreateClient(void);
uint32_t Kine_Gns_Connect(KineGnsHost *host, const char *address, uint16_t port);
bool Kine_Gns_Poll(KineGnsHost *host, KineGnsEvent *out_event);
bool Kine_Gns_Send(KineGnsHost *host, uint32_t peer, uint8_t channel,
                   const uint8_t *data, uint32_t size, bool reliable, bool unsequenced);
bool Kine_Gns_IsConnected(KineGnsHost *host, uint32_t peer);

bool Kine_Gns_IsActive(KineGnsHost *host, uint32_t peer);
void Kine_Gns_Flush(KineGnsHost *host);
void Kine_Gns_Close(KineGnsHost *host, uint32_t peer, bool immediate);
void Kine_Gns_Destroy(KineGnsHost *host);

#ifdef __cplusplus
}
#endif
