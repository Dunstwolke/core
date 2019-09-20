#ifndef API_HPP
#define API_HPP

#include "enums.hpp"
#include "types.hpp"
#include "resources.hpp"

/// this namespace implements all
/// possible "outer world" interactions.
namespace API
{
	void uploadResource(UIResourceID, ResourceKind, void const * data, size_t len);
	void addOrUpdateObject(Object && obj);
	void removeObject(ObjectID id);
	void setView(UIResourceID id);
	void setRoot(ObjectID obj);
	void setProperty(ObjectID obj, PropertyName prop, UIValue const & value); // "unsafe command", uses the serverside object type or fails of property does not exist
	void clear(ObjectID obj, PropertyName prop);
	void insertRange(ObjectID obj, PropertyName prop, size_t index, size_t count, ObjectRef const * value); // manipulate lists
	void removeRange(ObjectID obj, PropertyName prop, size_t index, size_t count); // manipulate lists
	void moveRange(ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count); // manipulate lists
}

#endif // API_HPP
