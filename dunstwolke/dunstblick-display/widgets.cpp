#include "widgets.hpp"
#include "resources.hpp"
#include "rectangle_tools.hpp"

#include <xlog>

static bool is_clicked(SDL_Rect const & rect, SDL_Event const & ev)
{
	if(ev.type != SDL_MOUSEBUTTONDOWN)
		return false;
	return contains(rect, ev.button.x, ev.button.y);
}

Spacer::Spacer()
{
	hitTestVisible.set(this, false);
}

void Spacer::paintWidget(const SDL_Rect &)
{

}

void Button::paintWidget(const SDL_Rect &rectangle)
{
    context().renderer.setColor(0x80, 0x80, 0x80);
    context().renderer.fillRect(rectangle);

    context().renderer.setColor(0xFF, 0xFF, 0xFF);
	context().renderer.drawRect(rectangle);
}

Button::Button() :
    ClickableWidget(UIWidget::button)
{

}

void Button::onClick()
{
	trigger_callback(onClickEvent.get(this));
}

Label::Label()
{
    margins.set(this, UIMargin(8));
    horizontalAlignment.set(this, HAlignment::center);
    verticalAlignment.set(this, VAlignment::middle);

	hitTestVisible.set(this, false);
}

void Label::paintWidget(const SDL_Rect &rectangle)
{
    auto & fc = context().getFont(font.get(this));
    auto * tex = fc.render(text.get(this));

    context().renderer.copy(tex, rectangle); // stretch for now...
}

UISize Label::calculateWantedSize()
{
    auto & fc = context().getFont(font.get(this));
    auto * tex = fc.render(text.get(this));
    if(not tex)
        return { 0, TTF_FontHeight(fc.font.get()) };
    UISize size;
    SDL_QueryTexture(tex, nullptr, nullptr, &size.w, &size.h);
    return size;
}

UISize PlaceholderWidget::calculateWantedSize()
{
    return { 32, 32 };
}

void PlaceholderWidget::paintWidget(const SDL_Rect &rectangle)
{
    context().renderer.setColor(0xFF, 0x00, 0xFF);
    context().renderer.fillRect(rectangle);

    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    context().renderer.drawLine(rectangle.x, rectangle.y, rectangle.x + rectangle.w, rectangle.y + rectangle.h);
    context().renderer.drawLine(rectangle.x + rectangle.w, rectangle.y, rectangle.x, rectangle.y + rectangle.h);
    context().renderer.drawRect(rectangle);
}

void Panel::paintWidget(const SDL_Rect &rectangle)
{
    context().renderer.setColor(0x30, 0x00, 0x30);
    context().renderer.fillRect(rectangle);

    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    context().renderer.drawRect(rectangle);
}

UISize Separator::calculateWantedSize()
{
    return { 5, 5 };
}

void Separator::paintWidget(const SDL_Rect &rectangle)
{
    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    if(rectangle.w > rectangle.h)
    {
        int y = rectangle.y + rectangle.h / 2;
        context().renderer.drawLine(rectangle.x, y, rectangle.x + rectangle.w, y);
    }
    else
    {
        int x = rectangle.x + rectangle.w / 2;
        context().renderer.drawLine(x, rectangle.y, x, rectangle.y + rectangle.h);
    }
}

UISize ProgressBar::calculateWantedSize()
{
    return { 256, 32 };
}

void ProgressBar::paintWidget(const SDL_Rect &rectangle)
{
    context().renderer.setColor(0x30, 0x30, 0x30);
    context().renderer.fillRect(rectangle);

    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    context().renderer.drawRect(rectangle);

    SDL_Rect progressArea = {
        rectangle.x + 1,
        rectangle.y + 1,
        int((value.get(this) - minimum.get(this)) * float(rectangle.w - 2) / (maximum.get(this) - minimum.get(this)) + 0.5f),
        rectangle.h - 2
    };

    context().renderer.setColor(0x00, 0x00, 0xFF);
    context().renderer.fillRect(progressArea);

    std::string caption;
    switch(displayProgress.get(this))
    {
    case DisplayProgressStyle::none:
        caption = "";
        break;
    case DisplayProgressStyle::percent:
        caption = std::to_string(int(100.0f * (value.get(this) - minimum.get(this)) / (maximum.get(this) - minimum.get(this)) + 0.5f)) + "%";
        break;
    case DisplayProgressStyle::absolute:
        caption = std::to_string(int(value.get(this) + 0.5f));
        break;
    }
    if(not caption.empty())
    {
        auto * tex = context().getFont(UIFont::sans).render(caption);

        int w,h;
        SDL_QueryTexture(tex, nullptr, nullptr, &w, &h);
        SDL_Rect label = {
            rectangle.x + (rectangle.w - w) / 2,
            rectangle.y + (rectangle.h - h) / 2,
            w, h
        };
        context().renderer.copy(tex, label);
    }
}

CheckBox::CheckBox() :
    ClickableWidget(UIWidget::checkbox)
{
    horizontalAlignment.set(this, HAlignment::left);
	verticalAlignment.set(this, VAlignment::middle);
}

void CheckBox::onClick()
{
	// TODO: Implement correct radio logic!
	isChecked.set(this, not isChecked.get(this));
}

UISize CheckBox::calculateWantedSize()
{
    return { 32, 32 };
}

void CheckBox::paintWidget(const SDL_Rect &rectangle)
{
    context().renderer.setColor(0x30, 0x30, 0x30);
    context().renderer.fillRect(rectangle);

    if(isChecked.get(this))
        context().renderer.setColor(0xD0, 0xD0, 0xD0);
    else
        context().renderer.setColor(0x40, 0x40, 0x40);

    context().renderer.fillRect({
        rectangle.x + 6,
        rectangle.y + 6,
        rectangle.w - 12,
        rectangle.h - 12,
    });

    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    context().renderer.drawRect(rectangle);
}

RadioButton::RadioButton() :
    ClickableWidget(UIWidget::radiobutton)
{
    horizontalAlignment.set(this, HAlignment::left);
	verticalAlignment.set(this, VAlignment::middle);
}

void RadioButton::onClick()
{
	// TODO: Implement correct radio logic!
	isChecked.set(this, not isChecked.get(this));
}

UISize RadioButton::calculateWantedSize()
{
    return { 32, 32 };
}

void RadioButton::paintWidget(const SDL_Rect &rectangle)
{
    int centerX = rectangle.x + rectangle.w / 2;
    int centerY = rectangle.y + rectangle.h / 2;
    int radiusA = std::min(rectangle.w, rectangle.h) / 2 - 1;
    int radiusB = radiusA - 6;

    UIPoint circleA[37], circleB[37];
    for(int i = 0; i <= 36; i++)
    {
        circleA[i].x = int(centerX + radiusA * sin(M_PI * i / 18.0));
        circleA[i].y = int(centerY + radiusA * cos(M_PI * i / 18.0));

        circleB[i].x = int(centerX + radiusB * sin(M_PI * i / 18.0));
        circleB[i].y = int(centerY + radiusB * cos(M_PI * i / 18.0));
    }

    if(isChecked.get(this))
        context().renderer.setColor(0xD0, 0xD0, 0xD0);
    else
        context().renderer.setColor(0x40, 0x40, 0x40);

    context().renderer.drawLines(circleB, 36);

    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    context().renderer.drawLines(circleA, 36);
}

UISize Slider::calculateWantedSize()
{
    return { 32, 32 };
}

void Slider::paintWidget(const SDL_Rect &rectangle)
{
    int const knobThick = 12;

    if(orientation.get(this) == Orientation::horizontal)
    {
        // horizontal slider

        int y = rectangle.y + rectangle.h / 2;

        context().renderer.setColor(0xFF, 0xFF, 0xFF);
        context().renderer.drawLine(
            rectangle.x + knobThick / 2,
            y,
            rectangle.x + rectangle.w - knobThick / 2,
            y
        );

        SDL_Rect knob {
            rectangle.x + int((rectangle.w - knobThick - 1) * (value.get(this) - minimum.get(this)) / (maximum.get(this) - minimum.get(this)) + 0.5f),
            rectangle.y,
            knobThick,
            rectangle.h
        };

        context().renderer.setColor(0xC0, 0xC0, 0xC0);
        context().renderer.fillRect(knob);

        context().renderer.setColor(0xFF, 0xFF, 0xFF);
        context().renderer.drawRect(knob);
    }
    else
    {
        // vertical slider

        int x = rectangle.x + rectangle.w / 2;

        context().renderer.setColor(0xFF, 0xFF, 0xFF);
        context().renderer.drawLine(
            x,
            rectangle.y + knobThick / 2,
            x,
            rectangle.y + rectangle.h - knobThick / 2
        );

        SDL_Rect knob {
            rectangle.x,
            rectangle.y + int((rectangle.h - knobThick - 1) * (value.get(this) - minimum.get(this)) / (maximum.get(this) - minimum.get(this)) + 0.5f),
            rectangle.w,
            knobThick,
        };

        context().renderer.setColor(0xC0, 0xC0, 0xC0);
        context().renderer.fillRect(knob);

        context().renderer.setColor(0xFF, 0xFF, 0xFF);
        context().renderer.drawRect(knob);
	}
}

bool Slider::processEvent(const SDL_Event & ev)
{
	int const knobThick = 12;
	bool const isHorizontal = orientation.get(this) == Orientation::horizontal;

	auto setSlider = [&](int x, int y)
	{
		float v;
		if(isHorizontal)
		{
			int pos = std::clamp(x - knobThick / 2 - actual_bounds.x, 0, actual_bounds.w - knobThick - 1);
			v = float(pos) / float(actual_bounds.w - knobThick - 1);
		}
		else
		{
			int pos = std::clamp(y - knobThick / 2 - actual_bounds.y, 0, actual_bounds.h - knobThick - 1);
			v = float(pos) / float(actual_bounds.h - knobThick - 1);
		}

		float const min = minimum.get(this);
		float const max = maximum.get(this);

		value.set(this, min + v * (max - min));
	};

	switch(ev.type)
	{
		case SDL_MOUSEBUTTONDOWN:
			captureMouse();
			setSlider(ev.button.x, ev.button.y);
			break;

		case SDL_MOUSEMOTION:
			if(hasMouseCaptured())
				setSlider(ev.motion.x, ev.motion.y);
			break;

		case SDL_MOUSEBUTTONUP:
			releaseMouse();
			break;
	}

	return Widget::processEvent(ev);
}

Picture::Picture()
{
    this->hitTestVisible.set(this, false);
}

void Picture::paintWidget(const SDL_Rect & rectangle)
{
	if(auto bmp = get_resource<BitmapResource>(image.get(this)); bmp)
	{
		auto const [ format, access, w, h ] = bmp->texture.query();

		float targetAspect = float(rectangle.w) / float(rectangle.h);
		float sourceAspect = float(w) / float(h);

		switch(scaling.get(this))
		{
			case ImageScaling::none:
			{
				int const clipped_w = std::min(w, rectangle.w);
				int const clipped_h = std::min(h, rectangle.h);
				context().renderer.copy(
					bmp->texture,
					SDL_Rect { rectangle.x, rectangle.y, clipped_w, clipped_h },
					SDL_Rect { 0, 0, clipped_w, clipped_h }
				);
				break;
			}
			case ImageScaling::stretch:
				context().renderer.copy(bmp->texture, rectangle);
				break;
			case ImageScaling::center:
			{
				context().renderer.copy(bmp->texture, {
					rectangle.x + (rectangle.w - w) / 2,
					rectangle.y + (rectangle.h - h) / 2,
					w,
					h
				});
				break;
			}

			case ImageScaling::contain:
			{
				float scale;
				if(w <= rectangle.w and h <= rectangle.h)
				{
					scale = 1.0f;
				}
				else
				{
					// scale down the image to fit
					scale = (sourceAspect > targetAspect) ? float(rectangle.w) / float(w) : float(rectangle.h) / float(h);
				}

				int const scaled_w = int(scale * w + 0.5f);
				int const scaled_h = int(scale * h + 0.5f);

				// just center the image as it is contained
				context().renderer.copy(bmp->texture, {
					rectangle.x + (rectangle.w - scaled_w) / 2,
					rectangle.y + (rectangle.h - scaled_h) / 2,
					scaled_w,
					scaled_h
				});
				break;
			}

			case ImageScaling::zoom:
			{
				float scale = (sourceAspect > targetAspect) ? float(rectangle.w) / float(w) : float(rectangle.h) / float(h);

				int scaled_w = int(scale * w + 0.5f);
				int scaled_h = int(scale * h + 0.5f);

				// just center the image as it is contained
				context().renderer.copy(bmp->texture, {
					rectangle.x + (rectangle.w - scaled_w) / 2,
					rectangle.y + (rectangle.h - scaled_h) / 2,
					scaled_w,
					scaled_h
				});
				break;
			}


			case ImageScaling::cover:
			{
				float scale = (sourceAspect < targetAspect) ? float(rectangle.w) / float(w) : float(rectangle.h) / float(h);

				int scaled_w = int(scale * w + 0.5f);
				int scaled_h = int(scale * h + 0.5f);

				// just center the image as it is contained
				context().renderer.copy(bmp->texture, {
					rectangle.x + (rectangle.w - scaled_w) / 2,
					rectangle.y + (rectangle.h - scaled_h) / 2,
					scaled_w,
					scaled_h
				});
				break;
			}
		}
	}
}

UISize Picture::calculateWantedSize()
{
	if(auto res = find_resource(image.get(this)); res and is_bitmap(*res))
	{
		auto [ format, access, w, h ] = std::get<BitmapResource>(*res).texture.query();
		return { w, h };
	}
	else
	{
		return Widget::calculateWantedSize();
	}
}

ClickableWidget::ClickableWidget(UIWidget _type) :
    Widget(_type)
{

}

bool ClickableWidget::isKeyboardFocusable() const
{
	return true;
}

SDL_SystemCursor ClickableWidget::getCursor(UIPoint const &) const
{
	return SDL_SYSTEM_CURSOR_HAND;
}

bool ClickableWidget::processEvent(const SDL_Event & event)
{
	if(event.type == SDL_MOUSEBUTTONUP)
	{
		onClick();
		xlog::log(xlog::verbose) << "clicked on a " << to_string(type) << " widget!";
		return true;
	}
	return Widget::processEvent(event);
}

UISize ScrollBar::calculateWantedSize()
{
	if(orientation.get(this) == Orientation::horizontal)
	{
		return UISize { 64, 24 };
	}
	else
	{
		return UISize { 24, 64 };
	}
}

void ScrollBar::paintWidget(const SDL_Rect & rectangle)
{
	float const progress = (value.get(this) - minimum.get(this)) / (maximum.get(this) - minimum.get(this));

	if(orientation.get(this) == Orientation::vertical)
	{
		SDL_Rect const topKnob = { rectangle.x, rectangle.y, knobSize, knobSize };
		SDL_Rect const botKnob = { rectangle.x, rectangle.y + rectangle.h - knobSize, knobSize, knobSize };

		SDL_Rect const slidKnob = {
		    rectangle.x,
		    rectangle.y + knobSize + int(progress * (rectangle.h - 3 * knobSize) + 0.5f),
		    knobSize,
		    knobSize
		};

		context().drawBevel(topKnob, Bevel::raised);
		context().drawBevel(botKnob, Bevel::raised);
		context().drawBevel(slidKnob, Bevel::raised);
	}
	else
	{
		SDL_Rect const leftKnob = { rectangle.x, rectangle.y, knobSize, knobSize };
		SDL_Rect const rightKnob = { rectangle.x + rectangle.w - knobSize, rectangle.y, knobSize, knobSize };

		SDL_Rect const slidKnob = {
		    rectangle.x + knobSize + int(progress * (rectangle.w - 3 * knobSize) + 0.5f),
		    rectangle.y,
		    knobSize,
		    knobSize
		};

		context().drawBevel(leftKnob, Bevel::raised);
		context().drawBevel(rightKnob, Bevel::raised);
		context().drawBevel(slidKnob, Bevel::raised);
	}
}

bool ScrollBar::processEvent(const SDL_Event & ev)
{
	float const minval = minimum.get(this);
	float const maxval = maximum.get(this);
	float const val = value.get(this);
	float const range = maxval - minval;
	float const progress = (val - minval) / range;
	float const clickperc = 0.05f;

	auto const rectangle = actual_bounds;
	if(orientation.get(this) == Orientation::vertical)
	{
		SDL_Rect const topKnob = { rectangle.x, rectangle.y, knobSize, knobSize };
		SDL_Rect const botKnob = { rectangle.x, rectangle.y + rectangle.h - knobSize, knobSize, knobSize };

		SDL_Rect const knobArea = {
		    rectangle.x,
		    rectangle.y + knobSize,
		    rectangle.w,
		    rectangle.h - 2 * knobSize,
		};

		SDL_Rect const slidKnob = {
		    rectangle.x,
		    rectangle.y + knobSize + int(progress * (rectangle.h - 3 * knobSize) + 0.5f),
		    knobSize,
		    knobSize
		};

		if(ev.type == SDL_MOUSEBUTTONUP)
			releaseMouse();

		if(hasMouseCaptured() and (ev.type == SDL_MOUSEMOTION))
		{
			// move knob here!

			int const y = std::clamp(ev.motion.y - knobArea.y - knobOffset, 0, knobArea.h - 1);

			float const p = float(y) / float(knobArea.h - 1);

			value.set(this, minval + range * p);

			return true;
		}

		if(is_clicked(topKnob, ev))
		{
			value.set(this, std::clamp(val - clickperc * range, minval, maxval));
			return true;
		}
		if(is_clicked(botKnob, ev))
		{
			value.set(this, std::clamp(val + clickperc * range, minval, maxval));
			return true;
		}
		if(is_clicked(slidKnob, ev))
		{
			knobOffset = ev.button.y - slidKnob.y;
			captureMouse();
			return true;
		}
		if(is_clicked(knobArea, ev))
		{
			if(ev.button.y < slidKnob.y)
				value.set(this, std::clamp(val - clickperc * range, minval, maxval));
			else
				value.set(this, std::clamp(val + clickperc * range, minval, maxval));
			return true;
		}
	}
	else
	{
		SDL_Rect const leftKnob = { rectangle.x, rectangle.y, knobSize, knobSize };
		SDL_Rect const rightKnob = { rectangle.x + rectangle.w - knobSize, rectangle.y, knobSize, knobSize };

		SDL_Rect const knobArea = {
		    rectangle.x + knobSize,
		    rectangle.y,
		    rectangle.w - 2 * knobSize,
		    rectangle.h,
		};

		SDL_Rect const slidKnob = {
		    rectangle.x + knobSize + int(progress * (rectangle.w - 3 * knobSize) + 0.5f),
		    rectangle.y,
		    knobSize,
		    knobSize
		};


		if(ev.type == SDL_MOUSEBUTTONUP)
			releaseMouse();

		if(hasMouseCaptured() and (ev.type == SDL_MOUSEMOTION))
		{
			// move knob here!

			int const y = std::clamp(ev.motion.x - knobArea.x - knobOffset, 0, knobArea.w - 1);

			float const p = float(y) / float(knobArea.w - 1);

			value.set(this, minval + range * p);

			return true;
		}

		if(is_clicked(leftKnob, ev))
		{
			value.set(this, std::clamp(val - clickperc * range, minval, maxval));
			return true;
		}
		if(is_clicked(rightKnob, ev))
		{
			value.set(this, std::clamp(val + clickperc * range, minval, maxval));
			return true;
		}
		if(is_clicked(slidKnob, ev))
		{
			knobOffset = ev.button.x - slidKnob.x;
			captureMouse();
			return true;
		}
		if(is_clicked(knobArea, ev))
		{
			if(ev.button.x < slidKnob.x)
				value.set(this, std::clamp(val - clickperc * range, minval, maxval));
			else
				value.set(this, std::clamp(val + clickperc * range, minval, maxval));
			return true;
		}

	}

	return Widget::processEvent(ev);
}

SDL_SystemCursor ScrollBar::getCursor(const UIPoint & p) const
{
	return SDL_SYSTEM_CURSOR_HAND;
}

ScrollView::ScrollView()
{
	horizontal_bar.orientation.set(&horizontal_bar,Orientation::horizontal);
	vertical_bar.orientation.set(&vertical_bar,Orientation::vertical);

	horizontal_bar.margins.set(&horizontal_bar, UIMargin(0));
	vertical_bar.margins.set(&vertical_bar, UIMargin(0));
}

void ScrollView::layoutChildren(const SDL_Rect & fullArea)
{
	auto area = calculateChildArea(fullArea);

    auto childArea = area;

    int extend_x = 0;
    int extend_y = 0;
    for(auto & child : children)
    {
        auto const child_size = child->wanted_size_with_margins();

        extend_x = std::max(extend_x, child_size.w - childArea.w);
        extend_y = std::max(extend_y, child_size.h - childArea.h);
    }

    horizontal_bar.maximum.set(this, extend_x);
    vertical_bar.maximum.set(this, extend_y);

    if(horizontal_bar.value.get(this) > horizontal_bar.maximum.get(this)) {
        horizontal_bar.value.set(this, extend_x);
    }

    if(vertical_bar.value.get(this) > vertical_bar.maximum.get(this)) {
        vertical_bar.value.set(this, extend_x);
    }

    childArea.x -= int(horizontal_bar.value.get(this) + 0.5f);
    childArea.y -= int(vertical_bar.value.get(this) + 0.5f);

	for(auto & child : children)
	{
        auto const child_size = child->wanted_size_with_margins();
		SDL_Rect child_rect = {
		    childArea.x,
		    childArea.y,
		    std::max(childArea.w, child_size.w),
		    std::max(childArea.h, child_size.h)
		};

        printf("%d×%d, %d×%d → %d×%d\n",
            childArea.w, childArea.h,
            child_size.w, child_size.h,
            child_rect.w, child_rect.h);

		child->layout(child_rect);
	}

	vertical_bar.layout(SDL_Rect {
		area.x + area.w,
	    area.y,
		horizontal_bar.wanted_size.w,
		area.h
	});

	horizontal_bar.layout(SDL_Rect {
		area.x,
		area.y + area.h,
		area.w,
		vertical_bar.wanted_size.h,
    });
}

SDL_Rect ScrollView::calculateChildArea(SDL_Rect rect)
{
    rect.w -= vertical_bar.wanted_size.w;
    rect.h -= horizontal_bar.wanted_size.h;
    return rect;
}

UISize ScrollView::calculateWantedSize()
{
	auto childSize = Widget::calculateWantedSize();

	horizontal_bar.wanted_size = horizontal_bar.calculateWantedSize();
	vertical_bar.wanted_size = vertical_bar.calculateWantedSize();

	childSize.w += horizontal_bar.wanted_size.w;
	childSize.h += vertical_bar.wanted_size.h;

    return childSize;
}

Widget *ScrollView::hitTest(int ssx, int ssy)
{
    if(not this->hitTestVisible.get(this))
		return nullptr;
	if(not contains(actual_bounds, ssx, ssy))
		return nullptr;

    if(contains(horizontal_bar.actual_bounds, ssx, ssy))
        return &horizontal_bar;
    if(contains(vertical_bar.actual_bounds, ssx, ssy))
        return &vertical_bar;

    auto const childArea = calculateChildArea(actual_bounds);
    if(not contains(childArea, ssx, ssy))
        return this;

	for(auto it = children.rbegin(); it != children.rend(); it++)
	{
        if(auto * child = (*it)->hitTest(ssx, ssy); child != nullptr)
			return child;
	}
	return this;
}

void ScrollView::paint()
{
    assert(SDL_RenderIsClipEnabled(context().renderer));
    auto const currentClipRect = context().renderer.getClipRect();

    SDL_Rect actual_clip_rect = intersect(currentClipRect, actual_bounds);
    if(actual_clip_rect.w * actual_clip_rect.h > 0)
    {
        auto const child_clip_rect = intersect(actual_clip_rect, calculateChildArea(actual_bounds));

        context().renderer.setClipRect(child_clip_rect);
        for(auto & child : children)
        {
            // only draw visible children
            if(child->getActualVisibility() == Visibility::visible)
                child->paint();
        }

        context().renderer.setClipRect(actual_clip_rect);

        horizontal_bar.paintWidget(horizontal_bar.actual_bounds);
        vertical_bar.paintWidget(vertical_bar.actual_bounds);

        context().renderer.setClipRect(currentClipRect);
    }
}

void ScrollView::paintWidget(const SDL_Rect &)
{
    assert(false and "should never be called!");
}

SDL_SystemCursor ScrollView::getCursor(const UIPoint & p) const
{
	if(contains(vertical_bar.actual_bounds, p.x, p.y))
		return vertical_bar.getCursor(p);
	if(contains(horizontal_bar.actual_bounds, p.x, p.y))
		return horizontal_bar.getCursor(p);
	return Widget::getCursor(p);
}

bool ScrollView::processEvent(const SDL_Event & ev)
{
    auto const routeEvent = [&](int x, int y) -> bool {
        if(contains(vertical_bar.actual_bounds, x, y))
            return vertical_bar.processEvent(ev);
        if(contains(horizontal_bar.actual_bounds, x, y))
            return horizontal_bar.processEvent(ev);
        return Widget::processEvent(ev);
    };

    switch(ev.type)
    {
    case SDL_MOUSEWHEEL:      return routeEvent(ev.wheel.x, ev.wheel.y);
    case SDL_MOUSEMOTION:     return routeEvent(ev.motion.x, ev.motion.y);
    case SDL_MOUSEBUTTONDOWN: return routeEvent(ev.button.x, ev.button.y);
    case SDL_MOUSEBUTTONUP:   return routeEvent(ev.button.x, ev.button.y);
    default:                  return Widget::processEvent(ev);
    }
}
