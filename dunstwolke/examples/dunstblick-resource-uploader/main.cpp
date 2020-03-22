#include <iostream>
#include <xio/simple>
#include <nlohmann/json.hpp>

#include "dunstblick.h"
#include "dunstblick-internal.hpp"

#include <xnet/socket>
#include <arpa/inet.h>
#include <thread>
#include <chrono>

int main(int argc, char ** argv)
{
    xnet::socket multicast_sock(AF_INET, SOCK_DGRAM, 0);

    // multicast_sock.set_option<int>(SOL_SOCKET, SO_REUSEADDR, 1);
    // multicast_sock.set_option<int>(SOL_SOCKET, SO_BROADCAST, 1);

    // multicast_sock.bind(xnet::parse_ipv4("0.0.0.0", DUNSTBLICK_DEFAULT_PORT));

    // multicast_sock.set_option<int>(SOL_SOCKET, IP_MULTICAST_LOOP, 1);

    auto const multicast_ep = xnet::parse_ipv4(DUNSTBLICK_MULTICAST_GROUP, DUNSTBLICK_DEFAULT_PORT);

    timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 50000;

    multicast_sock.set_option<timeval>(SOL_SOCKET, SO_RCVTIMEO, timeout);

    struct Client
    {
        std::string name;
        int tcp_port;
        xnet::endpoint udp_ep;
    };

    std::vector<Client> clients;

    for(int i = 0; i < 10; i++)
    {
        UdpDiscover discoverMsg;
        discoverMsg.header = UdpHeader::create(UDP_DISCOVER);

        ssize_t sendlen  = multicast_sock.write_to(multicast_ep, &discoverMsg, sizeof discoverMsg);
        if(sendlen < 0)
          perror("send failed");
        while(true) {
            UdpBaseMessage message;
            auto const [ len, sender ] = multicast_sock.read_from(&message, sizeof message);
            if(len < 0) {
                if(errno != ETIMEDOUT)
                    perror("receive failed");
                break;
            }
            if(len >= sizeof(UdpDiscoverResponse) and message.header.type == UDP_RESPOND_DISCOVER)
            {
                auto & resp = message.discover_response;
                if(resp.length < DUNSTBLICK_MAX_APP_NAME_LENGTH)
                    resp.name[resp.length] = 0;
                else
                    resp.name.back() = 0;

                Client client;

                client.name = std::string(resp.name.data());
                client.tcp_port = resp.tcp_port;
                client.udp_ep = sender;

                bool found = false;
                for(auto const & other : clients)
                {
                    if(client.tcp_port != other.tcp_port)
                        continue;
                    if(client.udp_ep != other.udp_ep)
                        continue;
                    found = true;
                    break;
                }
                if(found)
                    continue;
                clients.emplace_back(std::move(client));
            }
        }
    }

    for(auto const & client : clients)
    {
        printf(
            "%s:\n"
            "\tname: %s\n"
            "\tport: %d\n",
            xnet::to_string(client.udp_ep).c_str(),
            client.name.c_str(),
            client.tcp_port
            );
    }

    return 1;
}
/*

#define DBCHECKED(_X) do { \
		dunstblick_Error err = _X; \
		if(err != DUNSTBLICK_ERROR_NONE) \
		{ \
			printf("failed to execute " #_X ": %d\n", err); \
			return 1; \
		} \
	} while(0)

int main(int argc, char ** argv)
{
    if((argc <= 1) || (argc > 3))
	{
		fprintf(stderr,
			"usage: dunstblick-layout-tester [resource json] [server] [port]\n"
			"[resource json] required, json-file defining all resources\n"
		    "[server]      is the ui server hostname and optional (defaults to 127.0.0.1)\n"
		    "[port]        is the ui server port and option (defaults to 1309)\n");
		return 1;
	}

	char const * fileName = argv[1];
	char const * server = (argc > 2) ? argv[2] : "127.0.0.1";
	int portNum = (argc > 3) ? strtod(argv[3], NULL) : 1309;

    auto json_blob = xio::load_raw(fileName);
    auto const json = nlohmann::json::parse(json_blob.begin(), json_blob.end());

	dunstblick_Connection * con = dunstblick_Open(server, portNum);
	if(con == nullptr) {
		printf("Failed to establish connection!\n");
		return 1;
	}

    for(auto const & resource : json)
    {
        auto const id = resource.value("id", 0U);
        auto const type = resource.value("type", std::string("bitmap"));
        auto const file = resource.value("file", std::string(""));

        dunstblick_ResourceKind kind = DUNSTBLICK_RESOURCE_BITMAP;
        if(type == "drawing")
            kind = DUNSTBLICK_RESOURCE_DRAWING;
        else if(type == "layout")
            kind = DUNSTBLICK_RESOURCE_LAYOUT;

        auto const blob = xio::load_raw(file);

        DBCHECKED(dunstblick_UploadResource(con, id, kind, blob.data(), blob.size()));
    }
	dunstblick_Close(con);

	return 0;
}

*/
