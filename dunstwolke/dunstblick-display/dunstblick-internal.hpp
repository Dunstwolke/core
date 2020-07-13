#ifndef DUNSTBLICKINTERNAL_HPP
#define DUNSTBLICKINTERNAL_HPP

#include "dunstblick.h"

#include <array>
#include <cstdint>

#define DUNSTBLICK_DEFAULT_PORT 1309
#define DUNSTBLICK_MULTICAST_GROUP "224.0.0.1"
#define DUNSTBLICK_MAX_APP_NAME_LENGTH 64

#define PACKED __attribute__((packed))

/*******************************************************************************
 * UDP Discovery Protocol Messages                                              *
 *******************************************************************************/

enum UdpAnnouncementType
{
    UDP_DISCOVER,
    UDP_RESPOND_DISCOVER
};

struct PACKED UdpHeader
{
    static constexpr inline std::array<uint8_t, 4> real_magic = {0x73, 0xe6, 0x37, 0x28};
    std::array<uint8_t, 4> magic;
    uint16_t type;

    static UdpHeader create(UdpAnnouncementType type)
    {
        return {
            real_magic,
            uint16_t(type),
        };
    }
};

struct PACKED UdpDiscover
{
    UdpHeader header;
};

struct PACKED UdpDiscoverResponse
{
    UdpHeader header;
    uint16_t tcp_port;
    uint16_t length;
    std::array<char, DUNSTBLICK_MAX_APP_NAME_LENGTH> name;
};

union PACKED UdpBaseMessage
{
    UdpHeader header;
    UdpDiscover discover;
    UdpDiscoverResponse discover_response;
};

/*******************************************************************************
 * TCP Control Protocol Messages                                                *
 *******************************************************************************/

namespace TCP_API_VERSION_1 {

/// Protocol initiating message sent from the display client to
/// the UI provider.
struct PACKED TcpConnectHeader
{
    static inline constexpr std::array<uint8_t, 4> real_magic = {0x21, 0x06, 0xc1, 0x62};
    static inline constexpr uint16_t current_protocol_version = 1;

    // protocol header, must not be changed or reordered between
    // different protocol versions!
    std::array<uint8_t, 4> magic;
    uint16_t protocol_version;

    // data header
    std::array<char, 32> name;
    std::array<char, 32> password;
    uint32_t capabilities;
    uint16_t screenSizeX;
    uint16_t screenSizeY;
};

/// Response from the ui provider to the display client.
/// Is the direct answer to @ref TcpConnectHeader.
struct PACKED TcpConnectResponse
{
    uint32_t success;       ///< is `1` if the connection was successful, otherwise `0`.
    uint32_t resourceCount; ///< Number of resources that should be transferred to the display client.
};

/// Followed after the @ref TcpConnectResponse, `resourceCount` descriptors
/// are transferred to the display client.
struct PACKED TcpResourceDescriptor
{
    dunstblick_ResourceID id;       ///< The unique resource identifier.
    dunstblick_ResourceKind type;   ///< The type of the resource.
    uint32_t size;                  ///< Size of the resource in bytes.
    std::array<uint8_t, 8> siphash; ///< MD5sum of the resource data.
};

/// Followed after the set of @ref TcpResourceDescriptor
/// the display client answers with the number of required resources.
struct PACKED TcpResourceRequestHeader
{
    uint32_t request_count;
};

/// Sent `request_count` times by the display server after the
/// @ref TcpResourceRequestHeader.
struct PACKED TcpResourceRequest
{
    dunstblick_ResourceID id;
};

/// Sent after the last @ref TcpResourceRequest for each
/// requested resource. Each @ref TcpResourceHeader is followed by a
/// blob containing the resource itself.
struct PACKED TcpResourceHeader
{
    dunstblick_ResourceID id; ///< id of the resource
    uint32_t size;            ///< size of the transferred resource
};

} // namespace TCP_API_VERSION_1

using namespace TCP_API_VERSION_1;

#endif // DUNSTBLICKINTERNAL_HPP
