#ifndef TESTHOST_HPP
#define TESTHOST_HPP

#include <thread>
#include <xnet/socket>
#include <xstd/locked_value>
#include <queue>
#include <atomic>

#include "protocol.hpp"

/// Implementation of a connection host
/// that uses a thread and a local socket pair
/// to communicate with the server.
///
/// This allows easier testing and debugging.
struct TestHost
{
public:
	xstd::locked_value<std::queue<Packet>> to_server;
	xstd::locked_value<std::queue<Packet>> to_test;
	std::atomic_flag stop_flag;
	std::thread worker;

	TestHost();
	TestHost(TestHost const &) = delete;
	TestHost(TestHost &&) = delete;
	~TestHost();

	void send(std::uint8_t const * payload, size_t len);

	/// nonblockingly checks for a received packet
	std::optional<Packet> receive();

private: // helper constructor
	static void static_host_worker(TestHost*);

	void host_worker();
};

#endif // TESTHOST_HPP
