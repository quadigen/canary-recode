#include "steam_sockets.h"

#include <steam/steamnetworkingsockets.h>
#include <steam/isteamnetworkingsockets.h>
#include <steam/isteamnetworkingutils.h>

#include <array>
#include <chrono>
#include <cstring>
#include <deque>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

struct PendingEvent {
    int32_t type;
    HSteamNetConnection peer;
    uint8_t channel = 0;
    std::vector<uint8_t> data;
};

struct KineGnsHost {
    HSteamListenSocket listener = k_HSteamListenSocket_Invalid;
    HSteamNetPollGroup group = k_HSteamNetPollGroup_Invalid;
    int32_t max_peers = 1;
    int32_t send_rate_bytes_per_second = 4 * 1024 * 1024;
    std::unordered_set<HSteamNetConnection> peers;
    std::unordered_set<HSteamNetConnection> connected;
    std::deque<PendingEvent> pending;
    std::vector<uint8_t> delivered;
};


static ISteamNetworkingSockets *g_sockets = nullptr;
static int g_users = 0;
static std::unordered_set<KineGnsHost *> g_hosts;
static std::unordered_map<HSteamNetConnection, KineGnsHost *> g_connection_owners;
static std::unordered_map<HSteamListenSocket, KineGnsHost *> g_listener_owners;

static void on_connection_status(SteamNetConnectionStatusChangedCallback_t *status) {
    if (!g_sockets || !status)
        return;
    const HSteamNetConnection conn = status->m_hConn;
    const auto state = status->m_info.m_eState;
    KineGnsHost *host = nullptr;
    auto owner = g_connection_owners.find(conn);
    if (owner != g_connection_owners.end())
        host = owner->second;

    if (state == k_ESteamNetworkingConnectionState_Connecting &&
        status->m_info.m_hListenSocket != k_HSteamListenSocket_Invalid) {
        auto listener = g_listener_owners.find(status->m_info.m_hListenSocket);
        if (listener == g_listener_owners.end()) {
            g_sockets->CloseConnection(conn, 0, "Unknown listener", false);
            return;
        }
        host = listener->second;
        if (static_cast<int32_t>(host->peers.size()) >= host->max_peers ||
            g_sockets->AcceptConnection(conn) != k_EResultOK ||
            !g_sockets->SetConnectionPollGroup(conn, host->group)) {
            g_sockets->CloseConnection(conn, 0, "Connection refused", false);
            return;
        }
        host->peers.insert(conn);
        g_connection_owners[conn] = host;
        return;
    }

    if (!host)
        return;

    if (state == k_ESteamNetworkingConnectionState_Connected) {
        if (host->connected.insert(conn).second)
            host->pending.push_back({1, conn, 0, {}});
    } else if (state == k_ESteamNetworkingConnectionState_ClosedByPeer ||
               state == k_ESteamNetworkingConnectionState_ProblemDetectedLocally) {
        host->peers.erase(conn);
        if (host->connected.erase(conn) > 0 ||
            status->m_eOldState == k_ESteamNetworkingConnectionState_Connecting)
            host->pending.push_back({2, conn, 0, {}});
        g_connection_owners.erase(conn);
        g_sockets->CloseConnection(conn, 0, nullptr, false);
    }
}


static constexpr int kKineGnsSendBufferBytes = 8 * 1024 * 1024;


static constexpr int kKineGnsSendRateBytesPerSecond = 4 * 1024 * 1024;
static constexpr int kKineGnsMinimumSendRate = 16 * 1024;
static constexpr int kKineGnsMaximumSendRate = 64 * 1024 * 1024;

static std::array<SteamNetworkingConfigValue_t, 4> connection_options(
    int32_t send_rate_bytes_per_second) {
    std::array<SteamNetworkingConfigValue_t, 4> options;
    options[0].SetPtr(k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,
                      reinterpret_cast<void *>(on_connection_status));
    options[1].SetInt32(k_ESteamNetworkingConfig_SendBufferSize,
                        kKineGnsSendBufferBytes);
    options[2].SetInt32(k_ESteamNetworkingConfig_SendRateMin,
                        send_rate_bytes_per_second);
    options[3].SetInt32(k_ESteamNetworkingConfig_SendRateMax,
                        send_rate_bytes_per_second);
    return options;
}


static bool set_send_rate_on_scope(ESteamNetworkingConfigScope scope, intptr_t handle,
                                   int32_t previous, int32_t rate) {
    auto *utils = SteamNetworkingUtils();
    if (!utils)
        return false;
    const auto first = rate > previous ? k_ESteamNetworkingConfig_SendRateMax
                                       : k_ESteamNetworkingConfig_SendRateMin;
    const auto second = rate > previous ? k_ESteamNetworkingConfig_SendRateMin
                                        : k_ESteamNetworkingConfig_SendRateMax;
    return utils->SetConfigValue(first, scope, handle,
                                 k_ESteamNetworkingConfig_Int32, &rate) &&
           utils->SetConfigValue(second, scope, handle,
                                 k_ESteamNetworkingConfig_Int32, &rate);
}

extern "C" int32_t Kine_Gns_GetSendRate(KineGnsHost *host) {
    return host ? host->send_rate_bytes_per_second : 0;
}

extern "C" bool Kine_Gns_SetSendRate(KineGnsHost *host, int32_t rate) {
    if (!host || !g_sockets || rate < kKineGnsMinimumSendRate ||
        rate > kKineGnsMaximumSendRate)
        return false;
    const auto previous = host->send_rate_bytes_per_second;
    if (previous == rate)
        return true;
    if (host->listener != k_HSteamListenSocket_Invalid &&
        !set_send_rate_on_scope(k_ESteamNetworkingConfig_ListenSocket,
                                host->listener, previous, rate))
        return false;


    for (const auto peer : host->peers) {
        if (!set_send_rate_on_scope(k_ESteamNetworkingConfig_Connection,
                                    peer, previous, rate))
            return false;
    }
    host->send_rate_bytes_per_second = rate;
    return true;
}

static bool parse_address(const char *input, uint16_t port, SteamNetworkingIPAddr &output) {
    if (!input || !*input || std::strcmp(input, "0.0.0.0") == 0) {
        output.Clear();
        output.m_port = port;
        return true;
    }


    std::string ip = std::strcmp(input, "localhost") == 0 ? "127.0.0.1" : input;
    if (!output.ParseString(ip.c_str()))
        return false;
    output.m_port = port;
    return true;
}

extern "C" bool Kine_Gns_Init(void) {
    if (g_users > 0) {
        ++g_users;
        return true;
    }
    SteamNetworkingErrMsg error{};
    if (!GameNetworkingSockets_Init(nullptr, error))
        return false;
    g_sockets = SteamNetworkingSockets();
    if (!g_sockets) {
        GameNetworkingSockets_Kill();
        return false;
    }
    g_users = 1;
    return true;
}

extern "C" void Kine_Gns_Kill(void) {
    if (g_users <= 0 || --g_users != 0)
        return;
    if (!g_hosts.empty() || !g_connection_owners.empty() || !g_listener_owners.empty()) {

        g_users = 1;
        return;
    }
    g_sockets = nullptr;
    GameNetworkingSockets_Kill();
}

extern "C" uint32_t Kine_Gns_TimeMs(void) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch());
    return static_cast<uint32_t>(elapsed.count());
}

static KineGnsHost *make_host(int32_t max_peers) {
    if (!g_sockets || max_peers <= 0)
        return nullptr;
    auto host = std::make_unique<KineGnsHost>();
    host->max_peers = max_peers;
    host->send_rate_bytes_per_second = kKineGnsSendRateBytesPerSecond;
    host->group = g_sockets->CreatePollGroup();
    if (host->group == k_HSteamNetPollGroup_Invalid)
        return nullptr;
    KineGnsHost *result = host.release();
    g_hosts.insert(result);
    return result;
}

extern "C" KineGnsHost *Kine_Gns_CreateServer(const char *address, uint16_t port,
                                               int32_t max_peers) {
    SteamNetworkingIPAddr bind{};
    if (!parse_address(address, port, bind))
        return nullptr;
    auto *host = make_host(max_peers);
    if (!host)
        return nullptr;
    auto options = connection_options(host->send_rate_bytes_per_second);
    host->listener = g_sockets->CreateListenSocketIP(bind,
                                                     static_cast<int>(options.size()),
                                                     options.data());
    if (host->listener == k_HSteamListenSocket_Invalid) {
        Kine_Gns_Destroy(host);
        return nullptr;
    }
    g_listener_owners[host->listener] = host;
    return host;
}

extern "C" KineGnsHost *Kine_Gns_CreateClient(void) {
    return make_host(1);
}

extern "C" uint32_t Kine_Gns_Connect(KineGnsHost *host, const char *address,
                                      uint16_t port) {
    if (!host || !host->peers.empty())
        return 0;
    SteamNetworkingIPAddr remote{};
    if (!parse_address(address, port, remote))
        return 0;
    auto options = connection_options(host->send_rate_bytes_per_second);
    auto conn = g_sockets->ConnectByIPAddress(remote,
                                              static_cast<int>(options.size()),
                                              options.data());
    if (conn == k_HSteamNetConnection_Invalid)
        return 0;
    if (!g_sockets->SetConnectionPollGroup(conn, host->group)) {
        g_sockets->CloseConnection(conn, 0, "Poll group failure", false);
        return 0;
    }
    host->peers.insert(conn);
    g_connection_owners[conn] = host;
    return static_cast<uint32_t>(conn);
}

extern "C" bool Kine_Gns_Poll(KineGnsHost *host, KineGnsEvent *out_event) {
    if (!host || !out_event || !g_sockets)
        return false;
    host->delivered.clear();


    if (host->pending.empty()) {
        g_sockets->RunCallbacks();
        SteamNetworkingMessage_t *messages[32];
        const int count = g_sockets->ReceiveMessagesOnPollGroup(host->group, messages, 32);
        for (int i = 0; i < count; ++i) {
            auto *message = messages[i];
            if (host->connected.count(message->m_conn) != 0 &&
                message->m_cbSize > 0 && message->m_pData) {
                auto *bytes = static_cast<const uint8_t *>(message->m_pData);
                PendingEvent event{3, message->m_conn, bytes[0], {}};
                event.data.assign(bytes + 1, bytes + message->m_cbSize);
                host->pending.push_back(std::move(event));
            }
            message->Release();
        }
    }
    if (host->pending.empty())
        return false;
    auto event = std::move(host->pending.front());
    host->pending.pop_front();
    host->delivered = std::move(event.data);
    *out_event = {};
    out_event->type = event.type;
    out_event->peer = static_cast<uint32_t>(event.peer);
    out_event->channel = event.channel;
    out_event->data = host->delivered.empty() ? nullptr : host->delivered.data();
    out_event->data_size = static_cast<uint32_t>(host->delivered.size());
    return true;
}

extern "C" bool Kine_Gns_Send(KineGnsHost *host, uint32_t peer, uint8_t channel,
                               const uint8_t *data, uint32_t size,
                               bool reliable, bool unsequenced) {
    if (!host || !g_sockets ||
        host->connected.count(static_cast<HSteamNetConnection>(peer)) == 0 ||
        (size && !data) || size >= 512 * 1024)
        return false;
    std::vector<uint8_t> message;
    message.reserve(static_cast<size_t>(size) + 1);
    message.push_back(channel);
    if (size)
        message.insert(message.end(), data, data + size);
    const int flags = reliable ? k_nSteamNetworkingSend_ReliableNoNagle :
                      unsequenced ? k_nSteamNetworkingSend_UnreliableNoDelay :
                                    k_nSteamNetworkingSend_UnreliableNoNagle;
    return g_sockets->SendMessageToConnection(static_cast<HSteamNetConnection>(peer),
                                              message.data(), static_cast<uint32_t>(message.size()),
                                              flags, nullptr) == k_EResultOK;
}

extern "C" bool Kine_Gns_IsConnected(KineGnsHost *host, uint32_t peer) {
    return host && host->connected.count(static_cast<HSteamNetConnection>(peer)) != 0;
}

extern "C" bool Kine_Gns_IsActive(KineGnsHost *host, uint32_t peer) {
    return host && host->peers.count(static_cast<HSteamNetConnection>(peer)) != 0;
}

extern "C" void Kine_Gns_Flush(KineGnsHost *host) {
    if (!host || !g_sockets)
        return;
    for (auto peer : host->connected)
        g_sockets->FlushMessagesOnConnection(peer);
}

extern "C" void Kine_Gns_Close(KineGnsHost *host, uint32_t peer, bool immediate) {
    if (!host || !g_sockets)
        return;
    auto conn = static_cast<HSteamNetConnection>(peer);
    if (host->peers.erase(conn) == 0)
        return;
    host->connected.erase(conn);
    g_connection_owners.erase(conn);


    host->pending.push_back({2, conn, 0, {}});
    g_sockets->CloseConnection(conn, 0, immediate ? "Reset" : "Disconnected", !immediate);
}

extern "C" void Kine_Gns_Destroy(KineGnsHost *host) {
    if (!host)
        return;
    if (host->listener != k_HSteamListenSocket_Invalid) {
        g_listener_owners.erase(host->listener);
        g_sockets->CloseListenSocket(host->listener);
    }
    for (auto peer : host->peers) {
        g_connection_owners.erase(peer);
        g_sockets->CloseConnection(peer, 0, "Host shutdown", false);
    }
    if (host->group != k_HSteamNetPollGroup_Invalid)
        g_sockets->DestroyPollGroup(host->group);
    g_hosts.erase(host);
    delete host;
}
