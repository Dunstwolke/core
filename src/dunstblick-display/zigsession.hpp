#ifndef ZIGSESSION_HPP
#define ZIGSESSION_HPP

#include "session.hpp"
#include <dunstblick.h>

struct CommandBuffer;

struct ZigSessionApi
{
    void __attribute__((cdecl)) (*trigger_event)(ZigSessionApi * api, uint32_t cid, uint32_t widget);

    void __attribute__((cdecl)) (*trigger_propertyChanged)(ZigSessionApi * api,
                                                           uint32_t oid,
                                                           uint32_t name,
                                                           dunstblick_Value const * value);
};

struct ZigSession : Session
{
    ZigSessionApi * api;

    ZigSession(ZigSessionApi * api);

    // we don't allow pushing zig sessions around
    // they are referenced in outside code!
    ZigSession(ZigSession &&) = delete;
    ZigSession(ZigSession const &) = delete;

    void trigger_event(EventID cid, WidgetName widget) override;

    void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value) override;
};

#endif // NETWORKSESSION_HPP
