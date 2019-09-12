#ifndef WIDGET_HPP
#define WIDGET_HPP

#include "enums.hpp"
#include "types.hpp"

#include "inputstream.hpp"
#include "rendercontext.hpp"

#include <vector>
#include <memory>
#include <variant>
#include <functional>
#include <sdl2++/renderer>


// widget layouting algorithm:
// stage 1:
//   calculate bottom-to-top the wanted_size for each widget
// stage 2:
//   lay out top-to-bottom each widget into its parent container


struct Widget;

struct BaseProperty
{
    BaseProperty() = default;
    BaseProperty(BaseProperty const &) = delete;
    BaseProperty(BaseProperty &&) = default;
    virtual ~BaseProperty();

    virtual UIValue getValue() const = 0;

    virtual void setValue(UIValue const & val) = 0;
};

template<typename T>
struct property : BaseProperty
{
    T value;

    property(T const & _default = T()) : value(_default) { }

    UIValue getValue() const override {
        if constexpr(std::is_enum_v<T>)
            return uint8_t(value);
        else
            return value;
    }

    void setValue(const UIValue &val) override {
        if constexpr(std::is_enum_v<T>)
            value = T(std::get<uint8_t>(val));
        else
            value = std::get<T>(val);
    }

    property & operator= (T const & new_value) {
        bool will_be_changed = (value != new_value);
        value = new_value;
        if(will_be_changed)
            ; // TODO: trigger "value changed here"
        return *this;
    }

    operator T() const {
        return value;
    }

    T * operator-> () {
        return &value;
    }

    T const * operator-> () const {
        return &value;
    }
};

using GetPropertyFunction = std::function<BaseProperty * (Widget &)>;

struct MetaProperty
{
    UIProperty name;
    GetPropertyFunction getter;

    template<typename T, typename P>
    MetaProperty(UIProperty _name, property<P> T::*member) :
        name(_name),
        getter([=](Widget & w) { return &(static_cast<T*>(&w)->*member); })
    {

    }
};

struct MetaWidget
{
    static std::map<UIProperty, GetPropertyFunction> const defaultProperties;
    static MetaWidget const & get(UIWidget type);

    std::map<UIProperty, GetPropertyFunction> specializedProperties;

    MetaWidget(std::initializer_list<MetaProperty>);
};

struct Widget
{
public: // meta
    UIWidget const type;
public: // widget tree
    /// contains all child widgets
    std::vector<std::unique_ptr<Widget>> children;

public: // deserializable properties
    // generic
    property<HAlignment> horizontalAlignment = HAlignment::stretch;
    property<VAlignment> verticalAlignment = VAlignment::stretch;
    property<Visibility> visibility = Visibility::visible;
    property<UIMargin> margins = UIMargin(4);
    property<UIMargin> paddings = UIMargin(0);
    property<bool> enabled = true;

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
    SDL_Size wanted_size;

    /// the position of the widget on the screen after layouting
    /// NOTE: this does not include the margins of the widget!
    SDL_Rect actual_bounds;

    /// if set to `true`, this widget has been hidden by the
    /// layout, not by the user.
    bool hidden_by_layout = false;

protected:
    explicit Widget(UIWidget type);

public:
    virtual ~Widget() = default;

    /// stage1: calculates recursively the wanted size of all widgets.
    void updateWantedSize();

    /// stage2: recursivly lays out this widget and all child widgets.
    /// @param bounds the rectangle this widget should reside in.
    ///        These bounds will be reduced by the margins of the widget.
    ///        the widget will be positioned according to its alignments into this layout
    void layout(SDL_Rect const & bounds);

    /// draws the widget
    void paint();

    /// returns the bounds of the widget with margins
    SDL_Rect bounds_with_margins() const;

    /// returns the wanted_size of the widget with margins added
    SDL_Size wanted_size_with_margins() const;

    /// deserializes a single property or throws a "not supported exception"
    void setProperty(UIProperty property, UIValue value);

    /// returns the actual visibility of this widget.
    /// this takes user decision, layout and other stuff into account.
    Visibility getActualVisibility() const;

protected:
    /// stage1: calculates the space this widget wants to take.
    /// MUST refresh `wanted_size` field!
    /// the default is the maximum size of all its children combined
    virtual SDL_Size calculateWantedSize();

    /// stage2: recursively lays out all child elements to the widgets layout.
    /// the default layouting is "all children get their wanted size with alignment".
    /// note: this method should call layout(rect) on all its children!
    /// @param childArea the area where the children will be positioned in
    virtual void layoutChildren(SDL_Rect const & childArea);

    virtual void paintWidget(SDL_Rect const & rectangle);

public:
    static std::unique_ptr<Widget> create(UIWidget id);
};

template<UIWidget Type>
struct WidgetIs : Widget
{
    explicit WidgetIs() : Widget(Type) { }

    MetaWidget const & metaWidget() {
        return MetaWidget::get(Type);
    }
};

#endif // WIDGET_HPP
