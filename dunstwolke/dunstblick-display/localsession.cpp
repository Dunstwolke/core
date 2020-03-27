#include "localsession.hpp"

void LocalSession::update() {}

void LocalSession::trigger_event(CallbackID cid)
{
    if (onEvent)
        onEvent(cid);
}

void LocalSession::trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
{
    if (onPropertyChanged)
        onPropertyChanged(oid, name, value);
}
