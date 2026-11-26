#include "steam_sockets.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>
int main() {
    assert(Kine_Gns_Init());
    auto *server = Kine_Gns_CreateServer("127.0.0.1", 29087, 8);
    auto *client = Kine_Gns_CreateClient();
    assert(server && client);
    constexpr int32_t kDefaultRate = 4 * 1024 * 1024;
    assert(Kine_Gns_GetSendRate(server) == kDefaultRate);
    assert(Kine_Gns_GetSendRate(client) == kDefaultRate);
    assert(!Kine_Gns_SetSendRate(client, 0));
    assert(!Kine_Gns_SetSendRate(client, 16 * 1024 - 1));
    assert(!Kine_Gns_SetSendRate(client, 64 * 1024 * 1024 + 1));
    assert(Kine_Gns_GetSendRate(client) == kDefaultRate);

    assert(Kine_Gns_SetSendRate(server, 2 * 1024 * 1024));
    assert(Kine_Gns_SetSendRate(client, 2 * 1024 * 1024));
    assert(Kine_Gns_GetSendRate(server) == 2 * 1024 * 1024);
    assert(Kine_Gns_GetSendRate(client) == 2 * 1024 * 1024);
    auto client_peer = Kine_Gns_Connect(client, "localhost", 29087);
    assert(client_peer);
    bool connected = false, sent = false, received = false;
    uint32_t server_peer = 0;
    for (int i = 0; i < 2000 && !received; ++i) {
        KineGnsEvent event{};
        while (Kine_Gns_Poll(client, &event)) {
            if (event.type == 1) connected = true;
            if (event.type == 2) return 1;
        }
        while (Kine_Gns_Poll(server, &event)) {
            if (event.type == 1) server_peer = event.peer;
            if (event.type == 3) {
                const char expected[] = "Kinemium over GNS";
                assert(event.channel == 1 && event.data_size == sizeof(expected));
                assert(memcmp(event.data, expected, sizeof(expected)) == 0);
                received = true;
            }
        }
        if (connected && !sent) {
            const char message[] = "Kinemium over GNS";
            assert(Kine_Gns_Send(client, client_peer, 1,
                reinterpret_cast<const uint8_t *>(message), sizeof(message), true, false));
            sent = true;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    assert(connected && server_peer && received && Kine_Gns_IsConnected(server, server_peer));

    assert(Kine_Gns_SetSendRate(server, kDefaultRate));
    assert(Kine_Gns_SetSendRate(client, kDefaultRate));
    assert(Kine_Gns_GetSendRate(server) == kDefaultRate);
    assert(Kine_Gns_GetSendRate(client) == kDefaultRate);


    std::vector<uint8_t> block(256 * 1024, 0x7b);


    constexpr int kBulkCount = 23;
    const auto bulk_start = std::chrono::steady_clock::now();
    for (int i = 0; i < kBulkCount; ++i)
        assert(Kine_Gns_Send(client, client_peer, 1, block.data(),
                             static_cast<uint32_t>(block.size()), true, false));
    Kine_Gns_Flush(client);
    int bulk_received = 0;
    for (int i = 0; i < 6000 && bulk_received < kBulkCount; ++i) {
        KineGnsEvent event{};
        while (Kine_Gns_Poll(server, &event)) {
            if (event.type == 3) {
                assert(event.channel == 1 && event.data_size == block.size());
                assert(event.data[0] == 0x7b && event.data[event.data_size - 1] == 0x7b);
                ++bulk_received;
            }
        }
        while (Kine_Gns_Poll(client, &event)) {
            assert(event.type != 2);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    assert(bulk_received == kBulkCount);
    const auto bulk_elapsed = std::chrono::steady_clock::now() - bulk_start;
    assert(bulk_elapsed < std::chrono::seconds(14));
    Kine_Gns_Close(client, client_peer, false);
    bool client_disconnected = false, server_disconnected = false;
    for (int i = 0; i < 1000 && !(client_disconnected && server_disconnected); ++i) {
        KineGnsEvent event{};
        while (Kine_Gns_Poll(client, &event))
            if (event.type == 2 && event.peer == client_peer)
                client_disconnected = true;
        while (Kine_Gns_Poll(server, &event))
            if (event.type == 2 && event.peer == server_peer)
                server_disconnected = true;
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    assert(client_disconnected && server_disconnected);
    assert(!Kine_Gns_IsActive(server, server_peer));
    Kine_Gns_Destroy(client);
    Kine_Gns_Destroy(server);
    Kine_Gns_Kill();
    std::puts("GNS loopback PASS");
}
