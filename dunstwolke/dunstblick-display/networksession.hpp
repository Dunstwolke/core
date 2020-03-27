#ifndef NETWORKSESSION_HPP
#define NETWORKSESSION_HPP

#include "session.hpp"

#include <xnet/ip>
#include <xnet/socket>

struct CommandBuffer;

struct NetworkSession : Session
{
    xnet::socket sock;

    NetworkSession(xnet::endpoint const & target);

    // session implementation
    void update() override;

    void trigger_event(CallbackID cid) override;

    void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value) override;

    // network stuff
    void do_communication();

    void send_message(CommandBuffer const & buffer);

    void parse_and_exec_msg(Packet const & msg);
};

#endif // NETWORKSESSION_HPP
