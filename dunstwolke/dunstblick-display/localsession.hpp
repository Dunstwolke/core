#ifndef LOCALSESSION_HPP
#define LOCALSESSION_HPP

#include "session.hpp"

struct LocalSession : Session
{
    std::function<void(EventID, WidgetName)> onEvent;
    std::function<void(ObjectID, PropertyName, UIValue)> onPropertyChanged;

    void update() override;

    void trigger_event(EventID event, WidgetName widget) override;

    void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value) override;
};

#endif // LOCALSESSION_HPP
