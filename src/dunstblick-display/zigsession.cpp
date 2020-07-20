#include "zigsession.hpp"

namespace {
dunstblick_Value translate_value(UIValue const & value)
{
    dunstblick_Value result;
    switch (UIType(value.index())) {
        case UIType::integer: {
            result.type = DUNSTBLICK_TYPE_INTEGER;
            result.value.integer = std::get<int>(value);
            break;
        }
        case UIType::number: {
            result.type = DUNSTBLICK_TYPE_NUMBER;
            result.value.number = std::get<float>(value);
            break;
        }
        case UIType::string: {
            result.type = DUNSTBLICK_TYPE_STRING;
            result.value.string = std::get<std::string>(value).c_str();
            break;
        }
        case UIType::enumeration: {
            result.type = DUNSTBLICK_TYPE_ENUMERATION;
            result.value.enumeration = std::get<uint8_t>(value);
            break;
        }
        case UIType::margins: {
            result.type = DUNSTBLICK_TYPE_MARGINS;
            result.value.margins = std::get<UIMargin>(value);
            break;
        }
        case UIType::color: {
            result.type = DUNSTBLICK_TYPE_COLOR;
            result.value.color = std::get<UIColor>(value);
            break;
        }
        case UIType::size: {
            result.type = DUNSTBLICK_TYPE_SIZE;
            result.value.size = std::get<UISize>(value);
            break;
        }
        case UIType::point: {
            result.type = DUNSTBLICK_TYPE_POINT;
            result.value.point = std::get<UIPoint>(value);
            break;
        }
        case UIType::resource: {
            result.type = DUNSTBLICK_TYPE_RESOURCE;
            result.value.resource = std::get<UIResourceID>(value).value;
            break;
        }
        case UIType::boolean: {
            result.type = DUNSTBLICK_TYPE_BOOLEAN;
            result.value.boolean = std::get<bool>(value);
            break;
        }
        case UIType::object: {
            result.type = DUNSTBLICK_TYPE_OBJECT;
            result.value.object = std::get<ObjectRef>(value).id.value;
            break;
        }
        default: {
            assert(false and "unsupported");
        }
    };

    return result;
}

UIValue translate_value(dunstblick_Value const & src)
{
    switch (src.type) {
        case DUNSTBLICK_TYPE_INTEGER: {
            return UIValue{src.value.integer};
        }
        case DUNSTBLICK_TYPE_NUMBER: {
            return UIValue{src.value.number};
        }
        case DUNSTBLICK_TYPE_STRING: {
            return UIValue{std::string{src.value.string}};
        }
        case DUNSTBLICK_TYPE_ENUMERATION: {
            return UIValue{src.value.enumeration};
        }
        case DUNSTBLICK_TYPE_MARGINS: {
            return UIValue{UIMargin(src.value.margins)};
        }
        case DUNSTBLICK_TYPE_COLOR: {
            return UIValue{src.value.color};
        }
        case DUNSTBLICK_TYPE_SIZE: {
            return UIValue{src.value.size};
        }
        case DUNSTBLICK_TYPE_POINT: {
            return UIValue{src.value.point};
        }
        case DUNSTBLICK_TYPE_RESOURCE: {
            return UIValue{UIResourceID{src.value.resource}};
        }
        case DUNSTBLICK_TYPE_BOOLEAN: {
            return UIValue{src.value.boolean};
        }
        case DUNSTBLICK_TYPE_OBJECT: {
            return UIValue{ObjectRef{ObjectID{src.value.object}}};
        }
        case DUNSTBLICK_TYPE_OBJECTLIST: {
            return UIValue{ObjectList{}};
        }
        default: {
            assert(false and "not supported");
        }
    }
}

} // namespace

ZigSession::ZigSession(ZigSessionApi * api) : api(api) {}

void ZigSession::trigger_event(EventID cid, WidgetName widget)
{
    api->trigger_event(api, cid.value, widget.value);
}

void ZigSession::trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
{
    dunstblick_Value dbval = translate_value(value);
    api->trigger_propertyChanged(api, oid.value, name.value, &dbval);
}

extern "C"
{
    Object * object_create(uint32_t id)
    {
        try {
            return new Object(ObjectID{id});
        } catch (std::bad_alloc const &) {
            return nullptr;
        }
    }

    bool object_addProperty(Object * obj, uint32_t prop, dunstblick_Value const * value)
    {
        UIValue val = translate_value(*value);
        try {
            obj->add(PropertyName{prop}, val);
            return true;
        } catch (std::runtime_error const &) {
            return false;
        }
    }

    void object_destroy(Object * obj)
    {
        delete obj;
    }
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

    void zsession_addOrUpdateObject(ZigSession * session, Object * obj)
    {
        session->addOrUpdateObject(std::move(*obj));
        delete obj;
    }

    void zsession_removeObject(ZigSession * session, uint32_t obj)
    {
        session->removeObject(ObjectID{obj});
    }

    void zsession_setView(ZigSession * session, uint32_t id)
    {
        session->setView(UIResourceID{id});
    }

    void zsession_setRoot(ZigSession * session, uint32_t obj)
    {
        session->setRoot(ObjectID{obj});
    }

    void zsession_setProperty(ZigSession * session, uint32_t obj, uint32_t prop, dunstblick_Value const * value)
    {
        UIValue ui_value = translate_value(*value);
        session->setProperty(ObjectID{obj}, PropertyName{prop}, ui_value);
    }

    void zsession_clear(ZigSession * session, uint32_t obj, uint32_t prop)
    {
        session->clear(ObjectID{obj}, PropertyName{prop});
    }

    void zsession_insertRange(
        ZigSession * session, uint32_t obj, uint32_t prop, size_t index, size_t count, uint32_t const * values)
    {
        std::vector<ObjectRef> refs;
        refs.reserve(count);
        for (size_t i = 0; i < count; i++) {
            refs.emplace_back(ObjectID{values[i]});
        }

        session->insertRange(ObjectID{obj}, PropertyName{prop}, index, count, refs.data());
    }

    void zsession_removeRange(ZigSession * session, uint32_t obj, uint32_t prop, size_t index, size_t count)
    {
        session->removeRange(ObjectID{obj}, PropertyName{prop}, index, count);
    }

    void zsession_moveRange(
        ZigSession * session, uint32_t obj, uint32_t prop, size_t indexFrom, size_t indexTo, size_t count)
    {
        session->moveRange(ObjectID{obj}, PropertyName{prop}, indexFrom, indexTo, count);
    }
}