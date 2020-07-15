#include "tcphost.hpp"

#include <gsl/gsl>
#include <xlog>
#include <xcept>

TcpHost::TcpHost(int bindPort) :
    listener(AF_INET, SOCK_STREAM, 0),
    client(),
    worker(),
    packet_queue()
{
	if(not listener.bind(xnet::parse_ipv4("0.0.0.0", bindPort)))
		throw std::runtime_error("Could not bind listener!");

	if(not listener.listen())
		throw std::runtime_error("Could not listen!");

	this->shutdown_request.test_and_set();
	this->worker = std::thread([](TcpHost * host) { host->thread_worker(); }, this);
}

TcpHost::~TcpHost()
{
	this->listener.shutdown();
	this->shutdown_request.clear();
	this->client->shutdown();
	this->worker.join();
}

void TcpHost::send(const uint8_t * payload, size_t len)
{
	std::lock_guard _ { send_lock };
	xnet::socket_ostream stream { *this->client };
	stream.write<uint32_t>(gsl::narrow<uint32_t>(len));
	stream.write(payload, len);
}

std::optional<Packet> TcpHost::receive()
{
	std::lock_guard _ { queue_lock };
	if(packet_queue.size() > 0) {
		auto packet = std::move(packet_queue.front());
		packet_queue.pop();
		return std::move(packet);
	} else {
		return std::nullopt;
	}
}

void TcpHost::thread_worker()
{
	while(this->shutdown_request.test_and_set())
	{
		try
		{
			auto [ sock, ep ] = listener.accept();
			this->client.emplace(std::move(sock));
		}
		catch(xcept::io_error const & err)
		{
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
			XLOG_MSG() << err.what();
			continue;
		}

		XLOG_MSG() << "TCP Client connected!";
		try
		{
			auto stream = xnet::socket_istream { *this->client };

			bool connected = true;
			while(connected)
			{
				auto const length = stream.read<uint32_t>();
				if(length > 0)
				{
					Packet p(length);
					stream.read(p.data(), p.size());

					XLOG_MSG() << "TCP Client received " << p.size() << " bytes of data!";

					std::lock_guard _ { queue_lock };
					packet_queue.emplace(std::move(p));
				}
				else
				{
					connected = false;
				}
			}
		}
		catch(xcept::end_of_stream const &)
		{
			// client closed connection...
			XLOG_MSG() << "TCP Client disconnected!";
		}
		catch(xcept::io_error const & error)
		{
			// client closed connection...
			XLOG_ERROR() << "TCP Client failed: " << error.what();
		}


		this->client.reset();
	}
}
