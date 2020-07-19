#include "zigsession.hpp"

ZigSession::ZigSession(ZigSessionApi * api) : api(api)
{
    // TODO: Init API here
}
void ZigSession::trigger_event(EventID cid, WidgetName widget)
{
    api->trigger_event(api, cid.value, widget.value);
}

void ZigSession::trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
{
    dunstblick_Value dbval;
    // TODO: Implement c++ → zig translation here
    api->trigger_propertyChanged(api, oid.value, name.value, &dbval);
}

extern "C"
{
    ZigSession * zsession_create(ZigSessionApi * api)
    {
        try {
            return new ZigSession(api);
        } catch (std::bad_alloc const &) {
            return nullptr;
        }
    }

    void zsession_destroy(ZigSession * session)
    {
        delete session;
    }

    void zsession_uploadResource(
        ZigSession * session, uint32_t resource_id, ResourceKind kind, void const * data, size_t len)
    {
        session->uploadResource(UIResourceID(resource_id), kind, data, len);
    }

    void zsession_addOrUpdateObject(ZigSession * session, Object && obj)
    {
        assert(false and "not implemented yet");
    }

    void zsession_removeObject(ZigSession * session, uint32_t obj)
    {
        session->removeObject(ObjectID(obj));
    }

    void zsession_setView(ZigSession * session, uint32_t id)
    {
        session->setView(UIResourceID(id));
    }

    void zsession_setRoot(ZigSession * session, uint32_t obj)
    {
        session->setRoot(ObjectID(obj));
    }

    void zsession_setProperty(ZigSession * session, uint32_t obj, uint32_t prop, dunstblick_Value const & value)
    {
        assert(false and "not implemented yet");
    }

    void zsession_clear(ZigSession * session, uint32_t obj, uint32_t prop)
    {
        session->clear(ObjectID(obj), PropertyName(prop));
    }

    void zsession_insertRange(
        ZigSession * session, uint32_t obj, uint32_t prop, size_t index, size_t count, uint32_t const * value)
    {
        assert(false and "not implemented yet");
    }

    void zsession_removeRange(ZigSession * session, ObjectID obj, PropertyName prop, size_t index, size_t count)
    {
        assert(false and "not implemented yet");
    }

    void zsession_moveRange(
        ZigSession * session, ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count)
    {
        assert(false and "not implemented yet");
    }
}