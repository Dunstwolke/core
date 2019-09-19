#ifndef TCPHOST_HPP
#define TCPHOST_HPP

#include <xnet/socket>
#include <xnet/socket_stream>
#include <thread>
#include <queue>
#include <mutex>

#include "protocol.hpp"

struct TcpHost
{
	xnet::socket listener;
	std::optional<xnet::socket> client;
	std::thread worker;
	std::queue<Packet> packet_queue;
	std::mutex queue_lock;
	std::mutex send_lock;

	explicit TcpHost(int bindPort);
	TcpHost(TcpHost const &) = delete;
	TcpHost(TcpHost &&) = delete;
	~TcpHost();

	void send(std::uint8_t const * payload, size_t len);

	/// nonblockingly checks for a received packet
	std::optional<Packet> receive();

	void thread_worker();
};

#endif // TCPHOST_HPP
