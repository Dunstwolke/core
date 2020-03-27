#ifndef SESSION_HPP
#define SESSION_HPP

#include <mutex>
#include <vector>

#include "enums.hpp"
#include "resources.hpp"
#include "types.hpp"
#include "widget.hpp"

using Packet = std::vector<uint8_t>;

struct Widget;

struct Session : IWidgetContext
{
    std::unique_ptr<Widget> root_widget;
    Widget * keyboard_focused_widget = nullptr;
    Widget * mouse_focused_widget = nullptr;

    ObjectRef root_object = ObjectRef(nullptr);

    std::mutex send_lock;

    bool is_active = true;

    std::map<UIResourceID, Resource> resources;
    std::map<ObjectID, Object> object_registry;

    Session();
    Session(Session const &) = delete;
    virtual ~Session();

    virtual void update() = 0;

    xstd::optional<Object &> try_resolve(ObjectID) override;

    // API
    void uploadResource(UIResourceID, ResourceKind, void const * data, size_t len);
    void addOrUpdateObject(Object && obj);
    void removeObject(ObjectID id);
    void setView(UIResourceID id);
    void setRoot(ObjectID obj);
    void setProperty(
        ObjectID obj,
        PropertyName prop,
        UIValue const & value); // "unsafe command", uses the serverside object type or fails of property does not exist
    void clear(ObjectID obj, PropertyName prop);
    void insertRange(
        ObjectID obj, PropertyName prop, size_t index, size_t count, ObjectRef const * value);       // manipulate lists
    void removeRange(ObjectID obj, PropertyName prop, size_t index, size_t count);                   // manipulate lists
    void moveRange(ObjectID obj, PropertyName prop, size_t indexFrom, size_t indexTo, size_t count); // manipulate lists

    // Layouting and stuff
    void update_layout();
    void ui_set_mouse_focus(Widget * widget);
    void ui_set_keyboard_focus(Widget * widget);

    Widget * get_mouse_widget(int x, int y);

    // Resource handling:

    xstd::optional<Resource const &> find_resource(UIResourceID id) override;

    void set_resource(UIResourceID id, Resource && resource);

    // Object handling:

    Object & add_or_get_object(ObjectID id);

    Object & add_or_update_object(Object && obj);

    void destroy_object(ObjectID id);

    std::map<ObjectID, Object> const & get_object_registry();
};

#endif // SESSION_HPP
