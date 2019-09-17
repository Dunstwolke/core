#include "widget.hpp"
#include "resources.hpp"
#include <stdexcept>

#ifdef DEBUG
#include <iostream>
#endif

////////////////////////////////////////////////////////////////////////////////
/// Stage 1:
/// Determine widget sizes

Widget::Widget(UIWidget _type) :
  type(_type)
{

}

void Widget::updateBindings(ObjectRef parentBindingSource)
{
	// STAGE 1: Update the current binding source

	// if we have a bindingSource of the parent available:
	if(parentBindingSource and this->bindingContext.binding)
	{
		// check if the parent source has the property
		// we bind our bindingContext to and if yes,
		// bind to it
		if(auto prop = parentBindingSource->get(*this->bindingContext.binding); prop)
		{
			this->bindingSource = std::get<ObjectRef>(prop->value);
		}
		else
		{
			this->bindingSource = ObjectRef(nullptr);
		}
	}
	else
	{
		// otherwise check if our bindingContext has a valid resourceID and
		// load that resource reference:
		auto objectID = this->bindingContext.get(this);
		if(objectID.is_resolvable())
		{
			this->bindingSource = objectID;
		}
		else
		{
			this->bindingSource = parentBindingSource;
		}
	}

	// STAGE 2: Update child widgets.
	if(auto ct = childTemplate.get(this); not ct.is_null())
	{
		// if we have a child binding, update the child list
		auto list = childSource.get(this);
		if(this->children.size() != list.size())
			this->children.resize(list.size());
		for(size_t i = 0; i < list.size(); i++)
		{
			auto & child = this->children[i];
			if(not child or (child->templateID != ct)) {
				child = load_widget(ct);
			}

			// update the children with the list as
			// parent item:
			// this rebinds the logic such that each child
			// will bind to the list item instead
			// of the actual binding context :)
			child->updateBindings(list[i]);
		}
	}
	else
	{
		// if not, just update all children regulary
		for(auto & child : children)
			child->updateBindings(this->bindingSource);
	}
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
	if(children.empty())
		return sizeHint.get(this);

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
	  _bounds.x + margins.get(this).left,
	  _bounds.y + margins.get(this).top,
	  std::max(0, _bounds.w - margins.get(this).totalHorizontal()), // safety check against underflow
	  std::max(0, _bounds.h - margins.get(this).totalVertical()),
	};

	SDL_Rect target;
	switch(horizontalAlignment.get(this))
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

	switch(verticalAlignment.get(this))
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
	  this->actual_bounds.x + this->paddings.get(this).left,
	  this->actual_bounds.y + this->paddings.get(this).top,
	  this->actual_bounds.w - this->paddings.get(this).totalHorizontal(),
	  this->actual_bounds.h - this->paddings.get(this).totalVertical(),
	};

	this->layoutChildren(childArea);
}

void Widget::layoutChildren(SDL_Rect const & rect)
{
	for(auto & child : children)
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
	context().renderer.setClipRect(actual_bounds);

	// context().renderer.setColor(0xFF, 0x00, 0xFF, 0x40);
	// context().renderer.fillRect(actual_bounds);

	this->paintWidget(actual_bounds);

	context().renderer.resetClipRect();
	for(auto & child : children)
	{
		// only draw visible children
		if(child->getActualVisibility() == Visibility::visible)
			child->paint();
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

SDL_Size Widget::wanted_size_with_margins() const
{
	return {
		wanted_size.w + margins.get(this).totalHorizontal(),
		    wanted_size.h + margins.get(this).totalVertical(),
	};
}

void Widget::setProperty(UIProperty property, UIValue value)
{
	auto & meta = MetaWidget::get(this->type);

	if(auto it1 = meta.specializedProperties.find(property); it1 != meta.specializedProperties.end())
		it1->second(*this)->setValue(value);
	else if(auto it2 = meta.defaultProperties.find(property); it2 != meta.defaultProperties.end())
		it2->second(*this)->setValue(value);
	else {
#ifdef DEBUG
		std::cerr << "unknown property " + to_string(property) + " for widget " + to_string(this->type) + "!" << std::endl;
#else
		throw std::range_error("unknown property " + to_string(property) + " for widget " + to_string(this->type) + "!");
#endif
	}
}

void Widget::setPropertyBinding(UIProperty property, xstd::optional<PropertyName> name)
{
	auto & meta = MetaWidget::get(this->type);

	if(auto it1 = meta.specializedProperties.find(property); it1 != meta.specializedProperties.end())
		it1->second(*this)->binding = name;
	else if(auto it2 = meta.defaultProperties.find(property); it2 != meta.defaultProperties.end())
		it2->second(*this)->binding = name;
	else {
#ifdef DEBUG
		std::cerr << "unknown property " + to_string(property) + " for widget " + to_string(this->type) + "!" << std::endl;
#else
		throw std::range_error("unknown property " + to_string(property) + " for widget " + to_string(this->type) + "!");
#endif
	}
}

Visibility Widget::getActualVisibility() const
{
	if(hidden_by_layout)
		return Visibility::collapsed;
	return visibility.get(this);
}

static inline bool contains(SDL_Rect const & rect, int x, int y)
{
	return (x >= rect.x)
	   and (y >= rect.y)
	   and (x < rect.x + rect.w)
	   and (y < rect.y + rect.h)
	;
}

Widget * Widget::hitTest(int ssx, int ssy)
{
	if(not this->hitTestVisible.get(this))
		return nullptr;
	if(not contains(actual_bounds, ssx, ssy))
		return nullptr;
	for(auto it = children.rbegin(); it != children.rend(); it++)
	{
		if(auto * child = (*it)->hitTest(ssx, ssy); child != nullptr)
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

SDL_SystemCursor Widget::getCursor() const
{
	return SDL_SYSTEM_CURSOR_ARROW;
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
	MetaProperty { UIProperty::left, &Widget::left },
	MetaProperty { UIProperty::top, &Widget::top },
	MetaProperty { UIProperty::enabled, &Widget::enabled },
	MetaProperty { UIProperty::sizeHint, &Widget::sizeHint },
	MetaProperty { UIProperty::bindingContext, &Widget::bindingContext },
	MetaProperty { UIProperty::hitTestVisible, &Widget::hitTestVisible },
	MetaProperty { UIProperty::childSource, &Widget::childSource },
	MetaProperty { UIProperty::childTemplate, &Widget::childTemplate },
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
	{
		UIWidget::grid_layout,
		    MetaWidget
		{
			MetaProperty { UIProperty::columns, &GridLayout::columns },
			MetaProperty { UIProperty::rows, &GridLayout::rows },
		}
	},
	{
		UIWidget::picture,
		    MetaWidget
		{
			MetaProperty { UIProperty::image, &Picture::image },
			MetaProperty { UIProperty::imageScaling, &Picture::scaling },
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
