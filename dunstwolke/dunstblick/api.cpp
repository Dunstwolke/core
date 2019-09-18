#include "api.hpp"
#include "object.hpp"
#include "resources.hpp"
#include "rendercontext.hpp"

#include <SDL_image.h>

#include <xlog>

extern void set_ui_root(UIResourceID id);
extern void set_object_root(ObjectID id);

void API::uploadResource(UIResourceID id, ResourceKind kind, const void * data, size_t len)
{
	switch(kind)
	{
		case ResourceKind::layout:
		{
			set_resource(id, LayoutResource(reinterpret_cast<uint8_t const *>(data), len));
			break;
		}

		case ResourceKind::bitmap:
		{
			auto * tex = IMG_LoadTexture_RW(context().renderer, SDL_RWFromConstMem(data, gsl::narrow<int>(len)), 1);

			if(tex == nullptr) {
				xlog::log(xlog::error) << "could not load bitmap for resource " << id.value << ": " << SDL_GetError();
				return;
			}

			set_resource(id, BitmapResource(sdl2::texture(std::move(tex))));
			break;
		}

		case ResourceKind::drawing:
			assert(false and "not implemented yet!");
	}
}

void API::removeObject(ObjectID id)
{
	destroy_object(id);
}

void API::addOrUpdateObject(Object && obj)
{
	add_or_update_object(std::move(obj));
}

void API::setView(UIResourceID id)
{
	set_ui_root(id);
}

void API::setRoot(ObjectID obj)
{
	set_object_root(obj);
}

void API::setProperty(ObjectID oid, PropertyName propName, const UIValue & value)
{
	auto const type = UIType(value.index());
	if(auto obj = ObjectRef { oid }.try_resolve(); obj)
	{
		if(auto prop = obj->get(propName); prop)
		{
			if(prop->type == type)
			{
				prop->value = value;
			}
			else
			{
				xlog::log(xlog::error)
					<< "property " << propName.value
					<< " of object  " << oid.value
					<< " is of type " << to_string(prop->type)
					<< " but " << to_string(type)
					<< " was provided!"
				;
			}
		}
		else
		{
			xlog::log(xlog::error) << "object " << oid.value << " does not have the property " << propName.value << "!";
		}
	}
	else
	{
		xlog::log(xlog::error) << "object " << oid.value << " does not exist!";
	}
}

static inline xstd::optional<ObjectList &> get_list(ObjectID oid, PropertyName name)
{
	if(auto obj = ObjectRef { oid }.try_resolve(); obj)
	{
		if(auto prop = obj->get(name); prop)
		{
			if(prop->type == UIType::objectlist)
			{
				return std::get<ObjectList>(prop->value);
			}
			else
			{
				xlog::log(xlog::error)
					<< "property " << name.value
					<< " of object  " << oid.value
					<< " is of type " << to_string(prop->type)
					<< " instead of type objectlist!"
				;
			}
		}
		else
		{
			xlog::log(xlog::error) << "object " << oid.value << " does not have the property " << name.value << "!";
		}
	}
	else
	{
		xlog::log(xlog::error) << "object " << oid.value << " does not exist!";
	}
	return xstd::nullopt;
}

void API::clear(ObjectID obj, PropertyName prop)
{
	if(auto list = get_list(obj, prop); list)
	{
		list->clear();
	}
}

void API::insertRange(ObjectID obj, PropertyName prop, size_t index, size_t count, const ObjectRef * value)
{
	if(auto list = get_list(obj, prop); list)
	{
		for(size_t i = 0; i < count; i++, index++)
		{
			list->emplace((index >= list->size()) ? list->end() : list->begin() + index, value[i]);
		}
	}
}

void API::removeRange(ObjectID obj, PropertyName prop, size_t index, size_t count)
{
	if(auto list = get_list(obj, prop); list)
	{
		if(list->empty())
			return;
		for(size_t i = 0; (i < count) and (index < list->size()); i++, index++)
		{
			list->erase(list->begin() + index);
		}
	}
}

void API::moveRange(ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count)
{
	if(auto list = get_list(obj, prop); list)
	{
		assert(false and "not implemented yet!");
	}
}
