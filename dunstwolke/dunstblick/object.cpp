#include "object.hpp"

static std::map<ObjectID, Object> object_registry;

Object::Object(ObjectID id) :
    _id(id),
    properties()
{

}

ObjectProperty & Object::add(PropertyName name, UIType type)
{
	assert(not name.is_null());
	auto [ it, emplaced ] = properties.emplace(name, ObjectProperty { type, UIValue { } });
	if(not emplaced)
		throw std::runtime_error("object already has this property!");
	return it->second;
}

xstd::optional<ObjectProperty &> Object::get(PropertyName property)
{
	assert(not property.is_null());
	if(auto it = properties.find(property); it != properties.end())
		return it->second;
	else
		return xstd::nullopt;
}

xstd::optional<const ObjectProperty &> Object::get(PropertyName property) const
{
	assert(not property.is_null());
	if(auto it = properties.find(property); it != properties.end())
		return it->second;
	else
		return xstd::nullopt;
}


xstd::optional<Object &> ObjectRef::try_resolve()
{
	if(id.is_null())
		return xstd::nullopt;
	if(auto it = object_registry.find(id); it != object_registry.end())
		return it->second;
	else
		return xstd::nullopt;
}

xstd::optional<const Object &> ObjectRef::try_resolve() const
{
	if(id.is_null())
		return xstd::nullopt;
	if(auto it = object_registry.find(id); it != object_registry.end())
		return it->second;
	else
		return xstd::nullopt;
}

bool ObjectRef::is_resolvable() const
{
	return try_resolve().has_value();
}

Object & ObjectRef::resolve()
{
	if(auto obj = try_resolve(); obj)
		return *obj;
	else
		throw std::runtime_error("tried to access invalid object id " + std::to_string(id.value));
}

const Object & ObjectRef::resolve() const
{
	if(auto obj = try_resolve(); obj)
		return *obj;
	else
		throw std::runtime_error("tried to access invalid object id " + std::to_string(id.value));
}

Object & add_or_update_object(Object && obj)
{
	if(auto it = object_registry.find(obj.get_id()); it != object_registry.end()) {
		assert(it->first == obj.get_id());
		it->second = std::move(obj);
		return it->second;
	}
	auto [ it, emplaced ] = object_registry.emplace(obj.get_id(), std::move(obj));
	assert(emplaced);
	return it->second;
}

Object & add_or_get_object(ObjectID id)
{
	if(auto it = object_registry.find(id); it != object_registry.end()) {
		assert(it->first == id);
		return it->second;
	}
	auto [ it, emplaced ] = object_registry.emplace(id, Object { id });
	assert(emplaced);
	return it->second;
}

void destroy_object(ObjectID id)
{
	object_registry.erase(id);
}
