#include "widget.hpp"

#include <stdexcept>

////////////////////////////////////////////////////////////////////////////////
/// Stage 1:
/// Determine widget sizes

Widget::Widget(UIWidget _type) :
    type(_type)
{

}

void Widget::updateWantedSize()
{
    for(auto & child : children)
        child->updateWantedSize();

    this->wanted_size = this->calculateWantedSize();
    // this->wanted_size.w += this->margins.totalHorizontal();
    // this->wanted_size.h += this->margins.totalVertical();
}

SDL_Size Widget::calculateWantedSize()
{
    SDL_Size size = { 0, 0 };
    for(auto & child : children)
    {
        size.w = std::max(size.w, child->wanted_size_with_margins().w);
        size.h = std::max(size.h, child->wanted_size_with_margins().h);
    }
    return size;
}

////////////////////////////////////////////////////////////////////////////////
/// Stage 2:
/// Layouting

void Widget::layout(SDL_Rect const & _bounds)
{
    SDL_Rect const bounds = {
        _bounds.x + margins->left,
        _bounds.y + margins->top,
        std::max(0, _bounds.w - margins->totalHorizontal()), // safety check against underflow
        std::max(0, _bounds.h - margins->totalVertical()),
    };

    SDL_Rect target;
    switch(horizontalAlignment)
    {
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

    switch(verticalAlignment)
    {
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
        this->actual_bounds.x + this->paddings->left,
        this->actual_bounds.y + this->paddings->top,
        this->actual_bounds.w - this->paddings->totalHorizontal(),
        this->actual_bounds.h - this->paddings->totalVertical(),
    };

    this->layoutChildren(childArea);
}

void Widget::layoutChildren(SDL_Rect const & rect)
{
    for(auto & child : children)
        child->layout(rect);
}

////////////////////////////////////////////////////////////////////////////////
/// Stage 3:
/// Rendering

void Widget::paint(RenderContext & context)
{
    context.renderer.setClipRect(actual_bounds);

    context.renderer.setColor(0xFF, 0x00, 0xFF, 0x40);
    context.renderer.fillRect(actual_bounds);

    this->paintWidget(context, actual_bounds);

    context.renderer.resetClipRect();
    for(auto & child : children)
    {
        // only draw visible children
        if(child->getActualVisibility() == Visibility::visible)
            child->paint(context);
    }
}

SDL_Rect Widget::bounds_with_margins() const
{
    return {
        actual_bounds.x - margins->left,
        actual_bounds.y - margins->top,
        actual_bounds.w + margins->totalHorizontal(),
        actual_bounds.h + margins->totalVertical(),
    };
}

SDL_Size Widget::wanted_size_with_margins() const
{
    return {
        wanted_size.w + margins->totalHorizontal(),
        wanted_size.h + margins->totalVertical(),
    };
}

void Widget::setProperty(UIProperty property, UIValue value)
{
    auto & meta = MetaWidget::get(this->type);

    if(auto it = meta.specializedProperties.find(property); it != meta.specializedProperties.end())
        it->second(*this)->setValue(value);
    else if(auto it = meta.defaultProperties.find(property); it != meta.defaultProperties.end())
        it->second(*this)->setValue(value);
    else
        throw std::range_error("unknown property for this widget!");
}

Visibility Widget::getActualVisibility() const
{
    if(hidden_by_layout)
        return Visibility::collapsed;
    return visibility;
}

BaseProperty::~BaseProperty()
{

}







#include "widgets.hpp"
#include "layouts.hpp"

static std::map<UIProperty, GetPropertyFunction> Transpose(std::initializer_list<MetaProperty> props)
{
    std::map<UIProperty, GetPropertyFunction> properties;
    for(auto const & item : props)
        properties.emplace(item.name, item.getter);
    return properties;
}

std::map<UIProperty, GetPropertyFunction> const MetaWidget::defaultProperties = Transpose(
{
    MetaProperty { UIProperty::margins, &Widget::margins },
    MetaProperty { UIProperty::paddings, &Widget::paddings },
    MetaProperty { UIProperty::horizontalAlignment, &Widget::horizontalAlignment },
    MetaProperty { UIProperty::verticalAlignment, &Widget::verticalAlignment },
    MetaProperty { UIProperty::visibility, &Widget::visibility },
    MetaProperty { UIProperty::dockSite, &Widget::dockSite },
    MetaProperty { UIProperty::tabTitle, &Widget::tabTitle },
});

std::map<UIWidget, MetaWidget> const metaWidgets
{
    {
        UIWidget::label,
        MetaWidget
        {
            MetaProperty { UIProperty::text, &Label::text },
            MetaProperty { UIProperty::fontFamily, &Label::font },
        }
    },
    {
        UIWidget::spacer,
        MetaWidget
        {
            MetaProperty { UIProperty::sizeHint, &Spacer::sizeHint },
        }
    },
    {
        UIWidget::progressbar,
        MetaWidget
        {
            MetaProperty { UIProperty::minimum, &ProgressBar::minimum },
            MetaProperty { UIProperty::maximum, &ProgressBar::maximum },
            MetaProperty { UIProperty::value, &ProgressBar::value },
            MetaProperty { UIProperty::displayProgressStyle, &ProgressBar::displayProgress },
        }
    },
    {
        UIWidget::slider,
        MetaWidget
        {
            MetaProperty { UIProperty::minimum, &Slider::minimum },
            MetaProperty { UIProperty::maximum, &Slider::maximum },
            MetaProperty { UIProperty::value, &Slider::value },
        }
    },
    {
        UIWidget::stack_layout,
        MetaWidget
        {
            MetaProperty { UIProperty::stackDirection, &StackLayout::direction },
        }
    },
    {
        UIWidget::checkbox,
        MetaWidget
        {
            MetaProperty { UIProperty::isChecked, &CheckBox::isChecked },
        }
    },
    {
        UIWidget::radiobutton,
        MetaWidget
        {
            MetaProperty { UIProperty::isChecked, &RadioButton::isChecked },
        }
    },
    {
        UIWidget::tab_layout,
        MetaWidget
        {
            MetaProperty { UIProperty::selectedIndex, &TabLayout::selectedIndex },
        }
    },
};



const MetaWidget &MetaWidget::get(UIWidget type)
{
    static MetaWidget defaultWidget { };

    if(auto it = metaWidgets.find(type); it != metaWidgets.end())
        return it->second;
    else
        return defaultWidget;
}

MetaWidget::MetaWidget(std::initializer_list<MetaProperty> props)
{
    for(auto const & item : props)
        specializedProperties.emplace(item.name, item.getter);
}
