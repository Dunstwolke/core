#ifndef WIDGET_HPP
#define WIDGET_HPP

#include "enums.hpp"
#include "types.hpp"
#include "object.hpp"

#include "inputstream.hpp"
#include "rendercontext.hpp"

#include <vector>
#include <memory>
#include <variant>
#include <functional>
#include <sdl2++/renderer>

// #include <SDL.h>

// widget layouting algorithm:
// stage 1:
//   calculate bottom-to-top the wanted_size for each widget
// stage 2:
//   lay out top-to-bottom each widget into its parent container

// SDL_USEREVENT    = 0x8000,

#define UI_EVENT_GOT_MOUSE_FOCUS     (0x8000 + 0x1000)
#define UI_EVENT_LOST_MOUSE_FOCUS    (0x8000 + 0x1001)
#define UI_EVENT_GOT_KEYBOARD_FOCUS  (0x8000 + 0x1002)
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

template<typename T, bool UseBindings = true>
struct property : BaseProperty
{
private:
	T value;
public:

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

	UIType type() const override {
		return getUITypeFromType<T>();
	}

	// enforce "getter" everywhere
	T get(Widget const * w) const;

	void set(Widget * w, T const & value);
};

using GetPropertyFunction = std::function<BaseProperty * (Widget &)>;

template<typename T>
constexpr UIWidget widgetTypeToEnum();

template<> constexpr UIWidget widgetTypeToEnum<Widget>() { return UIWidget::invalid; }

#include "widget.mapper.hpp"

struct MetaProperty
{
	UIWidget widget;
	UIProperty name;
	GetPropertyFunction getter;

	template<typename T, typename P, bool B>
	MetaProperty(UIProperty _name, property<P,B> T::*member) :
	    widget(widgetTypeToEnum<T>()),
	    name(_name),
	    getter([=](Widget & w) {
			auto val = &(static_cast<T*>(&w)->*member);
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
	property<UISize> sizeHint = UISize { 0, 0 };
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
	SDL_Rect actual_bounds;

	/// if set to `true`, this widget has been hidden by the
	/// layout, not by the user.
	bool hidden_by_layout = false;

public: // binding system
	/// stores the object/ref to which properties will bind
	ObjectRef bindingSource = ObjectRef(nullptr);

protected:
	explicit Widget(UIWidget type);

public:
	virtual ~Widget();

	/// stage0: update widget bindings and property references.
	/// also updates child widgets if there are is a child source bound.
	void updateBindings(ObjectRef parentBindingSource);

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
	Widget * hitTest(int ssx, int ssy);

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

protected:
	/// stage1: calculates the space this widget wants to take.
	/// MUST refresh `wanted_size` field!
	/// the default is the maximum size of all its children combined
	virtual UISize calculateWantedSize();

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

/// loads a widget from a given resource ID or throws.
std::unique_ptr<Widget> load_widget(UIResourceID id);

extern void trigger_callback(CallbackID);

extern void trigger_propertyChanged(ObjectID, PropertyName, UIValue value);

template<typename T, bool UseBindings>
T property<T, UseBindings>::get(const Widget * w) const
{
	if constexpr (UseBindings) {
		if(binding and w->bindingSource.is_resolvable()) {
			if(auto prop = w->bindingSource->get(*binding); prop) {
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

template<typename T, bool UseBindings>
void property<T, UseBindings>::set(Widget * w, const T & new_value)
{
	if constexpr (UseBindings) {
		if(binding and w->bindingSource.is_resolvable()) {
			auto & obj = w->bindingSource.resolve();
			if(auto prop = obj.get(*binding); prop) {
				UIValue to_convert;
				if constexpr (std::is_enum_v<T>)
					to_convert = std::uint8_t(new_value);
				else
					to_convert = UIValue(new_value);

				auto const newValue = convertTo(to_convert, prop->type);
				auto const valueChanged = (prop->value != newValue);
				prop->value = newValue;
				if(valueChanged)
					trigger_propertyChanged(obj.get_id(), *binding, newValue);

				return;
			}
		}
	}
	this->value = new_value;
}

#endif // WIDGET_HPP
