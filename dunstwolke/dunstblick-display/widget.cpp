#include "widget.hpp"
#include "resources.hpp"

#include "rectangle_tools.hpp"
#include <stdexcept>
#include <xlog>

////////////////////////////////////////////////////////////////////////////////
/// Stage 1:
/// Determine widget sizes

Widget::Widget(UIWidget _type) : type(_type) {}

Widget::~Widget()
{
    // make sure the mouse is released if captured by this widget.
    if (capturingWidget == this)
        capturingWidget = nullptr;
}

void Widget::initializeRoot(IWidgetContext * context)
{
    assert(context != nullptr);
    this->widget_context = context;
    for (auto & child : children) {
        child->initializeRoot(context);
    }
}

void Widget::updateBindings(ObjectRef parentBindingSource)
{
    assert(widget_context != nullptr);

    // STAGE 1: Update the current binding source

    // if we have a bindingSource of the parent available:
    if (parentBindingSource.is_resolvable(*widget_context) and this->bindingContext.binding) {
        // check if the parent source has the property
        // we bind our bindingContext to and if yes,
        // bind to it
        if (auto prop = parentBindingSource.resolve(*widget_context).get(*this->bindingContext.binding); prop) {
            this->bindingSource = std::get<ObjectRef>(prop->value);
        } else {
            this->bindingSource = ObjectRef(nullptr);
        }
    } else {
        // otherwise check if our bindingContext has a valid resourceID and
        // load that resource reference:
        auto objectID = this->bindingContext.get(this);
        if (objectID.is_resolvable(*widget_context)) {
            this->bindingSource = objectID;
        } else {
            this->bindingSource = parentBindingSource;
        }
    }

    // STAGE 2: Update child widgets.
    if (auto ct = childTemplate.get(this); not ct.is_null()) {
        // if we have a child binding, update the child list
        auto list = childSource.get(this);
        if (this->children.size() != list.size())
            this->children.resize(list.size());
        for (size_t i = 0; i < list.size(); i++) {
            auto & child = this->children[i];
            if (not child or (child->templateID != ct)) {
                child = widget_context->load_widget(ct);
                child->initializeRoot(widget_context);
            }

            // update the children with the list as
            // parent item:
            // this rebinds the logic such that each child
            // will bind to the list item instead
            // of the actual binding context :)
            child->updateBindings(list[i]);
        }
    } else {
        // if not, just update all children regulary
        for (auto & child : children)
            child->updateBindings(this->bindingSource);
    }
}

void Widget::updateWantedSize()
{
    for (auto & child : children)
        child->updateWantedSize();

    this->wanted_size = this->calculateWantedSize();
    // this->wanted_size.w += this->margins.totalHorizontal();
    // this->wanted_size.h += this->margins.totalVertical();
}

UISize Widget::calculateWantedSize()
{
    auto const shint = sizeHint.get(this);

    if (children.empty())
        return shint;

    UISize size = {0, 0};
    for (auto & child : children) {
        size.w = std::max(size.w, child->wanted_size_with_margins().w);
        size.h = std::max(size.h, child->wanted_size_with_margins().h);
    }

    size.w = std::max(size.w, shint.w);
    size.h = std::max(size.h, shint.h);

    return size;
}

////////////////////////////////////////////////////////////////////////////////
/// Stage 2:
/// Layouting

void Widget::layout(SDL_Rect const & _bounds)
{
    SDL_Rect const bounds = {
        _bounds.x + margins.get(this).left,
        _bounds.y + margins.get(this).top,
        std::max(0, _bounds.w - margins.get(this).totalHorizontal()), // safety check against underflow
        std::max(0, _bounds.h - margins.get(this).totalVertical()),
    };

    SDL_Rect target;
    switch (horizontalAlignment.get(this)) {
        case HAlignment::stretch:
            target.w = bounds.w;
            target.x = 0;
            break;
        case HAlignment::left:
            target.w = std::min(wanted_size.w, bounds.w);
            target.x = 0;
            break;
        case HAlignment::center:
            target.w = std::min(wanted_size.w, bounds.w);
            target.x = (bounds.w - target.w) / 2;
            break;
        case HAlignment::right:
            target.w = std::min(wanted_size.w, bounds.w);
            target.x = bounds.w - target.w;
            break;
    }
    target.x += bounds.x;

    switch (verticalAlignment.get(this)) {
        case VAlignment::stretch:
            target.h = bounds.h;
            target.y = 0;
            break;
        case VAlignment::top:
            target.h = std::min(wanted_size.h, bounds.h);
            target.y = 0;
            break;
        case VAlignment::middle:
            target.h = std::min(wanted_size.h, bounds.h);
            target.y = (bounds.h - target.h) / 2;
            break;
        case VAlignment::bottom:
            target.h = std::min(wanted_size.h, bounds.h);
            target.y = bounds.h - target.h;
            break;
    }
    target.y += bounds.y;

    this->actual_bounds = target;

    SDL_Rect const childArea = {
        this->actual_bounds.x + this->paddings.get(this).left,
        this->actual_bounds.y + this->paddings.get(this).top,
        this->actual_bounds.w - this->paddings.get(this).totalHorizontal(),
        this->actual_bounds.h - this->paddings.get(this).totalVertical(),
    };

    this->layoutChildren(childArea);
}

void Widget::layoutChildren(SDL_Rect const & rect)
{
    for (auto & child : children)
        child->layout(rect);
}

void Widget::paintWidget(const SDL_Rect &)
{
    /* draw nothing by default */
}

////////////////////////////////////////////////////////////////////////////////
/// Stage 3:
/// Rendering

void Widget::paint()
{
    assert(SDL_RenderIsClipEnabled(context().renderer));
    auto const currentClipRect = context().renderer.getClipRect();

    SDL_Rect actual_clip_rect = intersect(currentClipRect, actual_bounds);
    if (actual_clip_rect.w * actual_clip_rect.h > 0) {
        context().renderer.setClipRect(actual_clip_rect);

        // context().renderer.setColor(0xFF, 0x00, 0xFF, 0x40);
        // context().renderer.fillRect(actual_bounds);

        this->paintWidget(actual_bounds);

        for (auto & child : children) {
            // only draw visible children
            if (child->getActualVisibility() == Visibility::visible)
                child->paint();
        }

        context().renderer.setClipRect(currentClipRect);
    }
}

SDL_Rect Widget::bounds_with_margins() const
{
    return {
        actual_bounds.x - margins.get(this).left,
        actual_bounds.y - margins.get(this).top,
        actual_bounds.w + margins.get(this).totalHorizontal(),
        actual_bounds.h + margins.get(this).totalVertical(),
    };
}

UISize Widget::wanted_size_with_margins() const
{
    return {
        wanted_size.w + margins.get(this).totalHorizontal(),
        wanted_size.h + margins.get(this).totalVertical(),
    };
}

void Widget::setProperty(UIProperty property, UIValue value)
{
    auto & meta = MetaWidget::get(this->type);

    if (auto it2 = meta.properties.find(property); it2 != meta.properties.end())
        it2->second(*this)->setValue(value);
    else {
        xlog::log(xlog::error) << "unknown property " + to_string(property) + " for widget " + to_string(this->type) +
                                      "!";
    }
}

void Widget::setPropertyBinding(UIProperty property, xstd::optional<PropertyName> name)
{
    auto & meta = MetaWidget::get(this->type);

    if (auto it = meta.properties.find(property); it != meta.properties.end())
        it->second(*this)->binding = name;
    else {
        xlog::log(xlog::error) << "unknown property " + to_string(property) + " for widget " + to_string(this->type) +
                                      "!";
    }
}

Visibility Widget::getActualVisibility() const
{
    if (hidden_by_layout)
        return Visibility::collapsed;
    return visibility.get(this);
}

Widget * Widget::hitTest(int ssx, int ssy)
{
    if (this->hidden_by_layout)
        return nullptr;
    if (not this->hitTestVisible.get(this))
        return nullptr;
    if (not contains(actual_bounds, ssx, ssy))
        return nullptr;
    for (auto it = children.rbegin(); it != children.rend(); it++) {
        if (auto * child = (*it)->hitTest(ssx, ssy); child != nullptr)
            return child;
    }
    return this;
}

bool Widget::processEvent(const SDL_Event &)
{
    // we don't do events by default
    return false;
}

bool Widget::isKeyboardFocusable() const
{
    return false;
}

SDL_SystemCursor Widget::getCursor(UIPoint const &) const
{
    return SDL_SYSTEM_CURSOR_ARROW;
}

void Widget::captureMouse()
{
    if ((capturingWidget != nullptr) and (capturingWidget != this))
        abort();
    capturingWidget = this;
}

void Widget::releaseMouse()
{
    capturingWidget = nullptr;
}

bool Widget::hasMouseCaptured()
{
    return (capturingWidget == this);
}

bool Widget::isMouseCaptured()
{
    return (capturingWidget != nullptr);
}

BaseProperty::~BaseProperty() {}

#include "layouts.hpp"
#include "widgets.hpp"

std::initializer_list<MetaProperty> const metaProperties{
    MetaProperty{UIProperty::name, &Widget::name},
    MetaProperty{UIProperty::margins, &Widget::margins},
    MetaProperty{UIProperty::paddings, &Widget::paddings},
    MetaProperty{UIProperty::horizontalAlignment, &Widget::horizontalAlignment},
    MetaProperty{UIProperty::verticalAlignment, &Widget::verticalAlignment},
    MetaProperty{UIProperty::visibility, &Widget::visibility},
    MetaProperty{UIProperty::dockSite, &Widget::dockSite},
    MetaProperty{UIProperty::tabTitle, &Widget::tabTitle},
    MetaProperty{UIProperty::left, &Widget::left},
    MetaProperty{UIProperty::top, &Widget::top},
    MetaProperty{UIProperty::enabled, &Widget::enabled},
    MetaProperty{UIProperty::sizeHint, &Widget::sizeHint},
    MetaProperty{UIProperty::bindingContext, &Widget::bindingContext},
    MetaProperty{UIProperty::hitTestVisible, &Widget::hitTestVisible},
    MetaProperty{UIProperty::childSource, &Widget::childSource},
    MetaProperty{UIProperty::childTemplate, &Widget::childTemplate},

    MetaProperty{UIProperty::text, &Label::text},
    MetaProperty{UIProperty::fontFamily, &Label::font},

    MetaProperty{UIProperty::minimum, &ProgressBar::minimum},
    MetaProperty{UIProperty::maximum, &ProgressBar::maximum},
    MetaProperty{UIProperty::value, &ProgressBar::value},
    MetaProperty{UIProperty::displayProgressStyle, &ProgressBar::displayProgress},

    MetaProperty{UIProperty::minimum, &Slider::minimum},
    MetaProperty{UIProperty::maximum, &Slider::maximum},
    MetaProperty{UIProperty::value, &Slider::value},
    MetaProperty{UIProperty::orientation, &Slider::orientation},

    MetaProperty{UIProperty::orientation, &StackLayout::direction},

    MetaProperty{UIProperty::isChecked, &CheckBox::isChecked},

    MetaProperty{UIProperty::isChecked, &RadioButton::isChecked},

    MetaProperty{UIProperty::selectedIndex, &TabLayout::selectedIndex},

    MetaProperty{UIProperty::columns, &GridLayout::columns},

    MetaProperty{UIProperty::rows, &GridLayout::rows},

    MetaProperty{UIProperty::image, &Picture::image},
    MetaProperty{UIProperty::imageScaling, &Picture::scaling},

    MetaProperty{UIProperty::onClick, &Button::onClickEvent},

    MetaProperty{UIProperty::orientation, &ScrollBar::orientation},
    MetaProperty{UIProperty::minimum, &ScrollBar::minimum},
    MetaProperty{UIProperty::maximum, &ScrollBar::maximum},
    MetaProperty{UIProperty::value, &ScrollBar::value},
};

static std::map<UIWidget, MetaWidget> widgetTypes;

const MetaWidget & MetaWidget::get(UIWidget type)
{
    if (auto it = widgetTypes.find(type); it != widgetTypes.end()) {
        return it->second;
    }
    auto [it, emplaced] = widgetTypes.emplace(type, MetaWidget{type});
    assert(emplaced);
    return it->second;
}

MetaWidget::MetaWidget(UIWidget type)
{
    for (auto const & item : metaProperties) {
        // invalid == root widget
        if ((item.widget == UIWidget::invalid) or (item.widget == type)) {
            properties.emplace(item.name, item.getter);
        }
    }
}

static std::unique_ptr<Widget> deserialize_widget(UIWidget widgetType, InputStream & stream)
{
    auto widget = Widget::create(widgetType);
    assert(widget);

    UIProperty property;
    do {
        bool isBinding;
        std::tie(property, isBinding) = stream.read_property_enum();
        if (property != UIProperty::invalid) {
            if (isBinding) {
                auto const name = PropertyName(stream.read_uint());
                widget->setPropertyBinding(property, name);
            } else {
                auto const value = stream.read_value(getPropertyType(property));
                widget->setProperty(property, value);
            }
        }
    } while (property != UIProperty::invalid);

    UIWidget childType;
    do {
        childType = stream.read_enum<UIWidget>();
        if (childType != UIWidget::invalid)
            widget->children.emplace_back(deserialize_widget(childType, stream));
    } while (childType != UIWidget::invalid);

    return widget;
}

static std::unique_ptr<Widget> deserialize_widget(InputStream & stream)
{
    auto const widgetType = stream.read_enum<UIWidget>();
    return deserialize_widget(widgetType, stream);
}

/// loads a widget from a given resource ID or throws.
std::unique_ptr<Widget> IWidgetContext::load_widget(UIResourceID id)
{
    if (auto resource = find_resource(id); resource) {
        if (resource->index() != int(ResourceKind::layout))
            throw std::runtime_error("invalid resource: wrong kind!");

        auto const & layout = std::get<LayoutResource>(*resource);

        InputStream stream = layout.get_stream();

        auto widget = deserialize_widget(stream);
        widget->templateID = id;
        return widget;
    } else {
        throw std::runtime_error("could not find the right resource!");
    }
}
