#include "localsession.hpp"

void LocalSession::update() {}

void LocalSession::trigger_event(EventID event, WidgetName widget)
{
    if (onEvent)
        onEvent(event, widget);
}

void LocalSession::trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
{
    if (onPropertyChanged)
        onPropertyChanged(oid, name, value);
}
