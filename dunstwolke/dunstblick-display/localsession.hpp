#ifndef LOCALSESSION_HPP
#define LOCALSESSION_HPP

#include "session.hpp"

struct LocalSession : Session
{
    std::function<void(CallbackID)> onEvent;
    std::function<void(ObjectID, PropertyName, UIValue)> onPropertyChanged;

    void update() override;

    void trigger_event(CallbackID cid) override;

    void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value) override;
};

#endif // LOCALSESSION_HPP
