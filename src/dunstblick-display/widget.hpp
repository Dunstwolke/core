#ifndef WIDGET_HPP
#define WIDGET_HPP

#include "enums.hpp"
#include "object.hpp"
#include "resources.hpp"
#include "types.hpp"

#include "inputstream.hpp"

#include <functional>
#include <memory>
#include <sdl2++/renderer>
#include <variant>
#include <vector>

// #include <SDL.h>

// widget layouting algorithm:
// stage 1:
//   calculate bottom-to-top the wanted_size for each widget
// stage 2:
//   lay out top-to-bottom each widget into its parent container

// SDL_USEREVENT    = 0x8000,

#define UI_EVENT_GOT_MOUSE_FOCUS (0x8000 + 0x1000)
#define UI_EVENT_LOST_MOUSE_FOCUS (0x8000 + 0x1001)
#define UI_EVENT_GOT_KEYBOARD_FOCUS (0x8000 + 0x1002)
#define UI_EVENT_LOST_KEYBOARD_FOCUS (0x8000 + 0x1003)

struct Widget;

struct BaseProperty
{
    xstd::optional<PropertyName> binding;

    BaseProperty() = default;
    BaseProperty(BaseProperty const &) = delete;
    BaseProperty(BaseProperty &&) = default;
    virtual ~BaseProperty();

    virtual UIType type() const = 0;

    /// NOTE: this ignores the binding!
    virtual UIValue getValue() const = 0;

    /// NOTE: this ignores the binding!
    virtual void setValue(UIValue const & val) = 0;
};

template <typename T, bool UseBindings = true>
struct property : BaseProperty
{
  private:
    T value;

  public:
    property(T const & _default = T()) : value(_default) {}

    UIValue getValue() const override
    {
        if constexpr (std::is_enum_v<T>)
            return uint8_t(value);
        else
            return value;
    }

    void setValue(const UIValue & val) override
    {
        if constexpr (std::is_enum_v<T>)
            value = T(std::get<uint8_t>(val));
        else
            value = std::get<T>(val);
    }

    UIType type() const override
    {
        return getUITypeFromType<T>();
    }

    // enforce "getter" everywhere
    T get(Widget const * w) const;

    void set(Widget * w, T const & value);
};

using GetPropertyFunction = std::function<BaseProperty *(Widget &)>;

template <typename T>
constexpr UIWidget widgetTypeToEnum();

template <>
constexpr UIWidget widgetTypeToEnum<Widget>()
{
    return UIWidget::invalid;
}

#include "widget.mapper.hpp"

struct MetaProperty
{
    UIWidget widget;
    UIProperty name;
    GetPropertyFunction getter;

    template <typename T, typename P, bool B>
    MetaProperty(UIProperty _name, property<P, B> T::*member) :
        widget(widgetTypeToEnum<T>()), name(_name), getter([=](Widget & w) {
            auto val = &(static_cast<T *>(&w)->*member);
            return val;
        })
    {
        assert(getUITypeFromType<P>() == getPropertyType(_name));
    }
};

struct MetaWidget
{
    static MetaWidget const & get(UIWidget type);

    std::map<UIProperty, GetPropertyFunction> properties;

    explicit MetaWidget(UIWidget);
};

struct IWidgetContext
{
    // Interface:

    virtual xstd::optional<Object &> try_resolve(ObjectID id) = 0;

    virtual void trigger_event(EventID event, WidgetName widget) = 0;

    virtual void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value) = 0;

    virtual xstd::optional<Resource const &> find_resource(UIResourceID id) = 0;

    virtual void notify_destroy(Widget * widget) = 0;

    // Helper functions:

    template <typename T>
    xstd::optional<T const &> get_resource(UIResourceID id)
    {
        if (auto res = find_resource(id); res and std::holds_alternative<T>(*res))
            return std::get<T>(*res);
        else
            return xstd::nullopt;
    }

    std::unique_ptr<Widget> load_widget(UIResourceID id);
};

enum class Bevel
{
    edge,           ///< A small border with a 3D effect, looks like a welding around the object
    crease,         ///< A small border with a 3D effect, looks like a crease around the object
    raised,         ///< A small border with a 3D effect, looks like the object is raised up from the surroundings
    sunken,         ///< A small border with a 3D effect, looks like the object is sunken into the surroundings
    input_field,    ///< The *deep* 3D border
    button_default, ///< Normal button outline
    button_pressed, ///< Pressed button outline
    button_active,  ///< Active button outline, not pressed
};

enum class LineStyle
{
    crease, ///< A small border with a 3D effect, looks like a welding around the object
    edge,   ///< A small border with a 3D effect, looks like a welding around the object
};

enum class Color
{
    background,
    input_field,
    highlight,
    checkered,
};

enum class TextAlign
{
    left,
    center,
    right,
    block
};

struct Rectangle : SDL_Rect
{
    explicit Rectangle() : SDL_Rect{0, 0, 0, 0} {}
    Rectangle(int _x, int _y, int _w, int _h) : SDL_Rect{_x, _y, _w, _h} {}

    explicit Rectangle(SDL_Rect const & r) : SDL_Rect{r} {}

    static inline Rectangle intersect(Rectangle const & a, Rectangle const & b)
    {
        auto const left = std::max(a.x, b.x);
        auto const top = std::max(a.y, b.y);

        auto const right = std::min(a.x + a.w, b.x + b.w);
        auto const bottom = std::min(a.y + a.h, b.y + b.h);

        if (right < left or bottom < top)
            return Rectangle{left, top, 0, 0};
        else
            return Rectangle{left, top, right - left, bottom - top};
    }

    inline bool contains(int px, int py) const
    {
        return (px >= this->x) and (py >= this->y) and (px < (this->x + this->w)) and (py < (this->y + this->h));
    }

    inline bool contains(SDL_Point const & p) const
    {
        return contains(p.x, p.y);
    }

    bool empty() const
    {
        return (w * h) == 0;
    }

    Rectangle shrink(int n) const
    {
        return Rectangle{x + n, y + n, w - 2 * n, h - 2 * n};
    }
};

struct IWidgetPainter
{
    /// Pushes a new clipping rectangle that will also be clipped against the previous one
    /// @returns the actual visible rectangle
    virtual Rectangle pushClipRect(Rectangle const & rect) = 0;

    virtual void popClipRect() = 0;

    virtual UISize measureString(std::string const & text, UIFont font, xstd::optional<int> line_width) const = 0;

    virtual void drawString(std::string const & text, Rectangle const & target, UIFont font, TextAlign align) = 0;

    virtual void drawRect(Rectangle const & rect, Bevel bevel) = 0;

    virtual void fillRect(Rectangle const & rect, Color color) = 0;

    virtual void drawIcon(Rectangle const & rect,
                          SDL_Texture * texture,
                          xstd::optional<Rectangle> clip_rect = xstd::nullopt) = 0;

    virtual void drawHLine(int startX, int startY, int width, LineStyle style) = 0;
    virtual void drawVLine(int startX, int startY, int height, LineStyle style) = 0;
};

struct Widget
{
  public:
    static inline Widget * capturingWidget = nullptr;

  public: // meta
    /// the type of the widget
    UIWidget const type;

    /// gets set by the deserializer on the root widget
    /// to the resource this widget was loaded from.
    std::optional<UIResourceID> templateID;

    /// Stores the context for this widget.
    /// Provides access to resources and event processing
    IWidgetContext * widget_context = nullptr;

  public: // widget tree
    /// contains all child widgets
    std::vector<std::unique_ptr<Widget>> children;

  public: // deserializable properties
    // generic
    property<WidgetName> name = WidgetName::null();
    property<HAlignment> horizontalAlignment = HAlignment::stretch;
    property<VAlignment> verticalAlignment = VAlignment::stretch;
    property<Visibility> visibility = Visibility::visible;
    property<UIMargin> margins = UIMargin(4);
    property<UIMargin> paddings = UIMargin(0);
    property<bool> enabled = true;
    property<UISize> sizeHint = UISize{0, 0};
    property<bool> hitTestVisible = true;

    property<ObjectList> childSource;
    property<UIResourceID> childTemplate;

    /// stores either a ResourceID or a property binding
    /// for the bindingSource. If the property is bound,
    /// it will bind to the parent bindingSource instead
    /// of the own bindingSource.
    /// see the implementation of @ref updateBindings
    property<ObjectRef, false> bindingContext = ObjectRef(nullptr);

    // dock layout
    property<DockSite> dockSite = DockSite::top;

    // tab layout
    property<std::string> tabTitle = std::string("Tab Page");

    // canvas layout
    property<int> left = 0;
    property<int> top = 0;

  public: // layouting and rendering
    /// the space the widget says it needs to have.
    /// this is a hint to each layouting algorithm to auto-size the widget
    /// accordingly.
    UISize wanted_size;

    /// the position of the widget on the screen after layouting
    /// NOTE: this does not include the margins of the widget!
    Rectangle actual_bounds;

    /// if set to `true`, this widget has been hidden by the
    /// layout, not by the user.
    bool hidden_by_layout = false;

  public: // binding system
    /// stores the object/ref to which properties will bind
    ObjectRef bindingSource = ObjectRef(nullptr);

  protected:
    explicit Widget(UIWidget type);
    Widget(Widget const &) = delete;

  public:
    virtual ~Widget();

    /// Sets the context for all resources and I/O operations for
    /// the widget and all its children.
    /// @remarks Call at least once before using.
    void initializeRoot(IWidgetContext * context);

    /// stage0: update widget bindings and property references.
    /// also updates child widgets if there are is a child source bound.
    void updateBindings(ObjectRef parentBindingSource);

    /// stage1: calculates recursively the wanted size of all widgets.
    void updateWantedSize(IWidgetPainter const &);

    /// stage2: recursivly lays out this widget and all child widgets.
    /// @param bounds the rectangle this widget should reside in.
    ///        These bounds will be reduced by the margins of the widget.
    ///        the widget will be positioned according to its alignments into this layout
    void layout(Rectangle const & bounds);

    /// draws the widget
    /// This function is a generic purpose painter
    virtual void paint(IWidgetPainter & painter);

    /// returns the bounds of the widget with margins
    Rectangle bounds_with_margins() const;

    /// returns the wanted_size of the widget with margins added
    UISize wanted_size_with_margins() const;

    /// sets a widget property or ignores the value if the property does not exist
    void setProperty(UIProperty property, UIValue value);

    /// sets the binding of a widget property
    void setPropertyBinding(UIProperty property, xstd::optional<PropertyName> name);

    /// returns the actual visibility of this widget.
    /// this takes user decision, layout and other stuff into account.
    Visibility getActualVisibility() const;

    /// performs a hit test against this widget and all
    /// possible children.
    /// @returns the widget hit.
    /// @param ssx x coordinate in screen space coordinates
    /// @param ssy y coordinate in screen space coordinates
    virtual Widget * hitTest(int ssx, int ssy);

    /// processes an SDL event that has been adjusted for this widget
    /// @param event the event that should be processed
    /// @returns true if the event was processed, false otherwise.
    virtual bool processEvent(SDL_Event const & event);

    /// returns true if the widget can be focused by keyboard selection
    virtual bool isKeyboardFocusable() const;

    /// returns the cursor for this widget
    virtual SDL_SystemCursor getCursor(UIPoint const & p) const;

    /// Will enforce that all future mouse input is redirected to
    /// this widget.
    /// @remarks will crash if the mouse is already captured by another widget
    ///          as this is a hard programming error!
    void captureMouse();

    /// will release the mouse from a previous capturing.
    void releaseMouse();

    /// returns true if this widget captures the mouse
    bool hasMouseCaptured();

    /// returns true if the mouse is captured by __any__ widget.
    bool isMouseCaptured();

    bool isFocused() const
    {
        return false;
    }

    bool isHovered() const
    {
        return false;
    }

    //! Gets the container where the logical children (from the layout)
    //! are contained in.
    virtual std::vector<std::unique_ptr<Widget>> & getChildContainer();

  protected:
    /// stage1: calculates the space this widget wants to take.
    /// MUST refresh `wanted_size` field!
    /// the default is the maximum size of all its children combined
    virtual UISize calculateWantedSize(IWidgetPainter const &);

    /// stage2: recursively lays out all child elements to the widgets layout.
    /// the default layouting is "all children get their wanted size with alignment".
    /// note: this method should call layout(rect) on all its children!
    /// @param childArea the area where the children will be positioned in
    virtual void layoutChildren(Rectangle const & childArea);

    virtual void paintWidget(IWidgetPainter & painter, Rectangle const & rectangle);

  public:
    static std::unique_ptr<Widget> create(UIWidget id);
};

template <UIWidget Type>
struct WidgetIs : Widget
{
    explicit WidgetIs() : Widget(Type) {}

    MetaWidget const & metaWidget()
    {
        return MetaWidget::get(Type);
    }
};

template <typename T, bool UseBindings>
T property<T, UseBindings>::get(const Widget * w) const
{
    if constexpr (UseBindings) {
        if (binding and w->bindingSource.is_resolvable(*w->widget_context)) {
            if (auto prop = w->bindingSource.resolve(*w->widget_context).get(*binding); prop) {
                auto const converted = convertTo(prop->value, getUITypeFromType<T>());
                if constexpr (std::is_enum_v<T>)
                    return T(std::get<uint8_t>(converted));
                else
                    return std::get<T>(converted);
            }
        }
    }
    return value;
}

template <typename T, bool UseBindings>
void property<T, UseBindings>::set(Widget * w, const T & new_value)
{
    if constexpr (UseBindings) {
        if (binding and w->bindingSource.is_resolvable(*w->widget_context)) {
            auto & obj = w->bindingSource.resolve(*w->widget_context);
            if (auto prop = obj.get(*binding); prop) {
                UIValue to_convert;
                if constexpr (std::is_enum_v<T>)
                    to_convert = std::uint8_t(new_value);
                else
                    to_convert = UIValue(new_value);

                auto const newValue = convertTo(to_convert, prop->type);
                auto const valueChanged = (prop->value != newValue);
                prop->value = newValue;
                if (valueChanged)
                    w->widget_context->trigger_propertyChanged(obj.get_id(), *binding, newValue);

                return;
            }
        }
    }
    this->value = new_value;
}

#endif // WIDGET_HPP