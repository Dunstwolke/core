#ifndef OBJECT_HPP
#define OBJECT_HPP

#include "types.hpp"

struct ObjectProperty
{
	UIType type;
	UIValue value;
};

struct ObjectProperty;
struct Object
{
private:
	ObjectID _id;
public:
	std::map<PropertyName, ObjectProperty> properties;

	explicit Object(ObjectID id);
	Object(Object const &) = delete;
	Object(Object &&) = default;

	Object & operator= (Object &&) = default;

	ObjectProperty & add(PropertyName, UIType type);

	ObjectID get_id() const {
		return _id;
	}

	ObjectProperty & add(PropertyName name, UIValue value)
	{
		auto & prop = add(name, UIType(value.index()));
		prop.value = std::move(value);
		return prop;
	}

	template<typename T>
	ObjectProperty & add(PropertyName name, T const & value)
	{
		auto & prop = add(name, getUITypeFromType<T>());
		prop.value = value;
		return prop;
	}

	xstd::optional<ObjectProperty&> get(PropertyName property);

	xstd::optional<ObjectProperty const &> get(PropertyName property) const;
};

Object & add_or_get_object(ObjectID id);

Object & add_or_update_object(Object && obj);

void destroy_object(ObjectID id);

#endif // OBJECT_HPP
