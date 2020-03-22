#ifndef DUNSTBLICKINTERNAL_HPP
#define DUNSTBLICKINTERNAL_HPP

#include "dunstblick.h"

#include <array>
#include <cstdint>

#define DUNSTBLICK_DEFAULT_PORT 1309
#define DUNSTBLICK_MULTICAST_GROUP "224.0.0.1"
#define DUNSTBLICK_MAX_APP_NAME_LENGTH 64

enum UdpAnnouncementType
{
    UDP_DISCOVER,
    UDP_RESPOND_DISCOVER
};

struct __attribute__((packed)) UdpHeader
{
    static constexpr inline std::array<uint8_t, 4> real_magic = { 0x73, 0xe6, 0x37, 0x28 };
    std::array<uint8_t, 4> magic;
    uint16_t type;

    static UdpHeader create(UdpAnnouncementType type) {
        return {
            real_magic,
            uint16_t(type),
        };
    }
};

struct __attribute__((packed)) UdpDiscover
{
    UdpHeader header;
};

struct __attribute__((packed)) UdpDiscoverResponse
{
    UdpHeader header;
    uint16_t tcp_port;
    uint16_t length;
    std::array<char, DUNSTBLICK_MAX_APP_NAME_LENGTH> name;
};

union __attribute__((packed)) UdpBaseMessage
{
    UdpHeader header;
    UdpDiscover discover;
    UdpDiscoverResponse discover_response;
};


#endif // DUNSTBLICKINTERNAL_HPP
