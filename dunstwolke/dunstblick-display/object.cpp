#include "object.hpp"
#include "session.hpp"

Object::Object(ObjectID id) : _id(id), properties() {}

ObjectProperty & Object::add(PropertyName name, UIType type)
{
    assert(not name.is_null());
    auto [it, emplaced] = properties.emplace(name, ObjectProperty{type, UIValue{}});
    if (not emplaced)
        throw std::runtime_error("object already has this property!");
    return it->second;
}

xstd::optional<ObjectProperty &> Object::get(PropertyName property)
{
    assert(not property.is_null());
    if (auto it = properties.find(property); it != properties.end())
        return it->second;
    else
        return xstd::nullopt;
}

xstd::optional<const ObjectProperty &> Object::get(PropertyName property) const
{
    assert(not property.is_null());
    if (auto it = properties.find(property); it != properties.end())
        return it->second;
    else
        return xstd::nullopt;
}

xstd::optional<Object &> ObjectRef::try_resolve(IWidgetContext & session)
{
    return session.try_resolve(this->id);
}

xstd::optional<const Object &> ObjectRef::try_resolve(IWidgetContext & session) const
{
    auto opt = session.try_resolve(this->id);
    if (opt)
        return *opt;
    else
        return xstd::nullopt;
}

bool ObjectRef::is_resolvable(IWidgetContext & session) const
{
    return try_resolve(session).has_value();
}

Object & ObjectRef::resolve(IWidgetContext & session)
{
    if (auto obj = try_resolve(session); obj)
        return *obj;
    else
        throw std::runtime_error("tried to access invalid object id " + std::to_string(id.value));
}

const Object & ObjectRef::resolve(IWidgetContext & session) const
{
    if (auto obj = try_resolve(session); obj)
        return *obj;
    else
        throw std::runtime_error("tried to access invalid object id " + std::to_string(id.value));
}
