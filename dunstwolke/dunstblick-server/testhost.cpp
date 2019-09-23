#include "testhost.hpp"
#include <xcept>
#include <xcept>
#include <cstring>
#include <iostream>
#include <iomanip>

TestHost::TestHost() :
    to_server(),
    to_test(),
    worker(static_host_worker, this)
{

}

TestHost::~TestHost()
{
	stop_flag.clear();
}

void TestHost::static_host_worker(TestHost * w)
{
	w->host_worker();
}

void TestHost::host_worker()
{
	stop_flag.test_and_set();
	while(stop_flag.test_and_set())
	{
		if(auto inbound = to_test.obtain(); inbound->size() > 0)
		{
			while(inbound->size() > 0)
			{
				auto packet = std::move(inbound->front());
				inbound->pop();

				std::cout << "received [";
				for(size_t i = 0; i < packet.size(); i++)
				{
					std::cout << " " << std::setw(2) << std::setfill('0') << std::hex << packet.at(i);
				}
				std::cout << " ] from ui server." << std::endl;

			}
		}

		std::this_thread::sleep_for(std::chrono::milliseconds(10));
	}
}

void TestHost::send(const uint8_t * payload, size_t len)
{
	to_test.obtain()->emplace(payload, payload + len);
}

std::optional<Packet> TestHost::receive()
{
	if(auto lock = to_server.obtain(); lock->size() > 0)
	{
		auto packed = std::move(lock->front());
		lock->pop();
		return std::move(packed);
	}
	else
	{
		return std::nullopt;
	}
}

