#include "widgets.hpp"
#include "resources.hpp"

#include <xlog>

static bool is_clicked(Rectangle const & rect, SDL_Event const & ev)
{
    if (ev.type != SDL_MOUSEBUTTONDOWN)
        return false;
    return rect.contains(ev.button.x, ev.button.y);
}

Spacer::Spacer()
{
    hitTestVisible.set(this, false);
}

void Spacer::paintWidget(IWidgetPainter & painter, const Rectangle &) {}

Container::Container() {}

void Container::paintWidget(IWidgetPainter &, const Rectangle &) {}

void Button::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    painter.fillRect(rectangle, Color::background);
    if (this->is_pressed) {
        painter.drawRect(rectangle, Bevel::button_pressed);
    } else {
        painter.drawRect(rectangle, this->isFocused() ? Bevel::button_active : Bevel::button_default);
    }
}

Button::Button() : ClickableWidget(UIWidget::button) {}

void Button::onClick()
{
    widget_context->trigger_event(onClickEvent.get(this), this->name.get(this));
}

Label::Label()
{
    margins.set(this, UIMargin(8));
    horizontalAlignment.set(this, HAlignment::center);
    verticalAlignment.set(this, VAlignment::middle);

    hitTestVisible.set(this, false);
}

void Label::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    painter.drawString(text.get(this), rectangle, font.get(this), TextAlign::left);
}

UISize Label::calculateWantedSize(IWidgetPainter const & painter)
{
    return painter.measureString(text.get(this), font.get(this), xstd::nullopt);
}

UISize PlaceholderWidget::calculateWantedSize(IWidgetPainter const &)
{
    return {32, 32};
}

void PlaceholderWidget::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    //    context().renderer.setColor(0xFF, 0x00, 0xFF);
    //    context().renderer.fillRect(rectangle);

    //    context().renderer.setColor(0xFF, 0xFF, 0xFF);
    //    context().renderer.drawLine(rectangle.x, rectangle.y, rectangle.x + rectangle.w, rectangle.y + rectangle.h);
    //    context().renderer.drawLine(rectangle.x + rectangle.w, rectangle.y, rectangle.x, rectangle.y + rectangle.h);
    //    context().renderer.drawRect(rectangle);
}

void Panel::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    painter.fillRect(rectangle, Color::background);
    painter.drawRect(rectangle, Bevel::crease);
}

UISize Separator::calculateWantedSize(IWidgetPainter const &)
{
    return {5, 5};
}

void Separator::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    if (rectangle.w > rectangle.h) {
        int y = rectangle.y + rectangle.h / 2;
        painter.drawHLine(rectangle.x, y, rectangle.w, LineStyle::edge);
    } else {
        int x = rectangle.x + rectangle.w / 2;
        painter.drawVLine(x, rectangle.y, rectangle.h, LineStyle::edge);
    }
}

UISize ProgressBar::calculateWantedSize(IWidgetPainter const &)
{
    return {256, 32};
}

void ProgressBar::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    painter.fillRect(rectangle, Color::input_field);

    Rectangle progressArea = {rectangle.x + 1,
                              rectangle.y + 1,
                              size_t(int((value.get(this) - minimum.get(this)) * float(rectangle.w - 2) /
                                             (maximum.get(this) - minimum.get(this)) +
                                         0.5f)),
                              rectangle.h - 2};

    painter.fillRect(progressArea, Color::highlight);

    std::string caption;
    switch (displayProgress.get(this)) {
        case DisplayProgressStyle::none:
            caption = "";
            break;
        case DisplayProgressStyle::percent:
            caption =
                std::to_string(int(
                    100.0f * (value.get(this) - minimum.get(this)) / (maximum.get(this) - minimum.get(this)) + 0.5f)) +
                "%";
            break;
        case DisplayProgressStyle::absolute:
            caption = std::to_string(int(value.get(this) + 0.5f));
            break;
    }
    if (not caption.empty()) {
        painter.drawString(caption, rectangle, UIFont::sans, TextAlign::center);
    }

    painter.drawRect(rectangle, Bevel::input_field);
}

CheckBox::CheckBox() : ClickableWidget(UIWidget::checkbox)
{
    horizontalAlignment.set(this, HAlignment::left);
    verticalAlignment.set(this, VAlignment::middle);
}

void CheckBox::onClick()
{
    // TODO: Implement correct radio logic!
    isChecked.set(this, not isChecked.get(this));
}

UISize CheckBox::calculateWantedSize(IWidgetPainter const &)
{
    return {32, 32};
}

void CheckBox::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    painter.fillRect(rectangle, Color::background);

    painter.drawRect(rectangle, isChecked.get(this) ? Bevel::button_pressed : Bevel::button_default);
}

RadioButton::RadioButton() : ClickableWidget(UIWidget::radiobutton)
{
    horizontalAlignment.set(this, HAlignment::left);
    verticalAlignment.set(this, VAlignment::middle);
}

void RadioButton::onClick()
{
    // TODO: Implement correct radio logic!
    isChecked.set(this, not isChecked.get(this));
}

UISize RadioButton::calculateWantedSize(IWidgetPainter const &)
{
    return {32, 32};
}

void RadioButton::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    painter.fillRect(rectangle, Color::background);

    painter.drawRect(rectangle, isChecked.get(this) ? Bevel::button_pressed : Bevel::button_default);
}

UISize Slider::calculateWantedSize(IWidgetPainter const &)
{
    return {32, 32};
}

void Slider::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    int const knobThick = 12;

    Rectangle knob;
    if (orientation.get(this) == Orientation::horizontal) {
        // horizontal slider

        int y = rectangle.y + rectangle.h / 2;

        painter.drawHLine(rectangle.x, y, rectangle.w, LineStyle::crease);

        knob = Rectangle{rectangle.x + int((rectangle.w - knobThick - 1) * (value.get(this) - minimum.get(this)) /
                                               (maximum.get(this) - minimum.get(this)) +
                                           0.5f),
                         rectangle.y,
                         knobThick,
                         rectangle.h};
    } else {
        // vertical slider

        int x = rectangle.x + rectangle.w / 2;

        painter.drawVLine(x, rectangle.y, rectangle.h, LineStyle::crease);

        knob = Rectangle{
            rectangle.x,
            rectangle.y + int((rectangle.h - knobThick - 1) * (value.get(this) - minimum.get(this)) /
                                  (maximum.get(this) - minimum.get(this)) +
                              0.5f),
            rectangle.w,
            knobThick,
        };
    }

    painter.fillRect(knob, Color::background);
    painter.drawRect(knob, isFocused() ? Bevel::button_active : Bevel::button_default);
}

bool Slider::processEvent(const SDL_Event & ev)
{
    int const knobThick = 12;
    bool const isHorizontal = orientation.get(this) == Orientation::horizontal;

    auto setSlider = [&](int x, int y) {
        float v;
        if (isHorizontal) {
            int pos = std::clamp<ssize_t>(x - knobThick / 2 - actual_bounds.x, 0, actual_bounds.w - knobThick - 1);
            v = float(pos) / float(actual_bounds.w - knobThick - 1);
        } else {
            int pos = std::clamp<ssize_t>(y - knobThick / 2 - actual_bounds.y, 0, actual_bounds.h - knobThick - 1);
            v = float(pos) / float(actual_bounds.h - knobThick - 1);
        }

        float const min = minimum.get(this);
        float const max = maximum.get(this);

        value.set(this, min + v * (max - min));
    };

    switch (ev.type) {
        case SDL_MOUSEBUTTONDOWN:
            captureMouse();
            setSlider(ev.button.x, ev.button.y);
            break;

        case SDL_MOUSEMOTION:
            if (hasMouseCaptured())
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

void Picture::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    if (auto bmp = widget_context->get_resource<BitmapResource>(image.get(this)); bmp) {
        auto const [w, h] = bmp->size;

        float targetAspect = float(rectangle.w) / float(rectangle.h);
        float sourceAspect = float(w) / float(h);

        switch (scaling.get(this)) {
            case ImageScaling::none: {
                size_t const clipped_w = std::min<size_t>(w, rectangle.w);
                size_t const clipped_h = std::min<size_t>(h, rectangle.h);
                painter.drawIcon(
                    Rectangle{
                        rectangle.x,
                        rectangle.y,
                        clipped_w,
                        clipped_h,
                    },
                    bmp->texture,
                    Rectangle{0, 0, clipped_w, clipped_h});
                break;
            }
            case ImageScaling::stretch:
                painter.drawIcon(rectangle, bmp->texture);
                break;
            case ImageScaling::center: {
                painter.drawIcon(
                    {
                        ssize_t(rectangle.x + (rectangle.w - w) / 2),
                        ssize_t(rectangle.y + (rectangle.h - h) / 2),
                        w,
                        h,
                    },
                    bmp->texture);
                break;
            }

            case ImageScaling::contain: {
                float scale;
                if (w <= rectangle.w and h <= rectangle.h) {
                    scale = 1.0f;
                } else {
                    // scale down the image to fit
                    scale =
                        (sourceAspect > targetAspect) ? float(rectangle.w) / float(w) : float(rectangle.h) / float(h);
                }

                size_t const scaled_w = size_t(scale * w + 0.5f);
                size_t const scaled_h = size_t(scale * h + 0.5f);

                // just center the image as it is contained
                painter.drawIcon(
                    {
                        ssize_t(rectangle.x + (rectangle.w - scaled_w) / 2),
                        ssize_t(rectangle.y + (rectangle.h - scaled_h) / 2),
                        scaled_w,
                        scaled_h,
                    },
                    bmp->texture);
                break;
            }

            case ImageScaling::zoom: {
                float scale =
                    (sourceAspect > targetAspect) ? float(rectangle.w) / float(w) : float(rectangle.h) / float(h);

                size_t scaled_w = size_t(scale * w + 0.5f);
                size_t scaled_h = size_t(scale * h + 0.5f);

                // just center the image as it is contained
                painter.drawIcon(
                    {
                        ssize_t(rectangle.x + (rectangle.w - scaled_w) / 2),
                        ssize_t(rectangle.y + (rectangle.h - scaled_h) / 2),
                        scaled_w,
                        scaled_h,
                    },
                    bmp->texture);
                break;
            }

            case ImageScaling::cover: {
                float scale =
                    (sourceAspect < targetAspect) ? float(rectangle.w) / float(w) : float(rectangle.h) / float(h);

                size_t scaled_w = size_t(scale * w + 0.5f);
                size_t scaled_h = size_t(scale * h + 0.5f);

                // just center the image as it is contained
                painter.drawIcon(
                    {
                        ssize_t(rectangle.x + (rectangle.w - scaled_w) / 2),
                        ssize_t(rectangle.y + (rectangle.h - scaled_h) / 2),
                        scaled_w,
                        scaled_h,
                    },
                    bmp->texture);
                break;
            }
        }
    }
}

UISize Picture::calculateWantedSize(IWidgetPainter const & painter)
{
    if (auto res = widget_context->find_resource(image.get(this)); res and is_bitmap(*res)) {
        return std::get<BitmapResource>(*res).size;
    } else {
        return Widget::calculateWantedSize(painter);
    }
}

ClickableWidget::ClickableWidget(UIWidget _type) : Widget(_type) {}

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
    int mx, my;
    SDL_GetMouseState(&mx, &my);

    if (event.type == SDL_MOUSEBUTTONDOWN) {
        this->captureMouse();
        this->is_pressed = true;
        this->is_pressable = true;
        return true;
    }

    if (this->is_pressable) {
        if (event.type == SDL_MOUSEMOTION) {
            this->is_pressed = this->actual_bounds.contains(event.motion.x, event.motion.y);
        }
    }

    if (event.type == SDL_MOUSEBUTTONUP) {
        this->releaseMouse();
        if (this->is_pressed) {
            onClick();
        }
        this->is_pressable = false;
        this->is_pressed = false;
        return true;
    }
    return Widget::processEvent(event);
}

UISize ScrollBar::calculateWantedSize(IWidgetPainter const &)
{
    if (orientation.get(this) == Orientation::horizontal) {
        return UISize{64, 24};
    } else {
        return UISize{24, 64};
    }
}

void ScrollBar::paintWidget(IWidgetPainter & painter, const Rectangle & rectangle)
{
    float const progress = (value.get(this) - minimum.get(this)) / (maximum.get(this) - minimum.get(this));

    painter.fillRect(rectangle, Color::checkered);

    if (orientation.get(this) == Orientation::vertical) {
        Rectangle const topKnob = {rectangle.x, rectangle.y, knobSize, knobSize};
        Rectangle const botKnob = {rectangle.x, ssize_t(rectangle.y + rectangle.h - knobSize), knobSize, knobSize};

        Rectangle const slidKnob = {
            rectangle.x,
            ssize_t(rectangle.y + knobSize + int(progress * (rectangle.h - 3 * knobSize) + 0.5f)),
            knobSize,
            knobSize};

        painter.fillRect(topKnob, Color::background);
        painter.fillRect(botKnob, Color::background);
        painter.fillRect(slidKnob, Color::background);

        painter.drawRect(topKnob, Bevel::button_default);
        painter.drawRect(botKnob, Bevel::button_default);
        painter.drawRect(slidKnob, Bevel::button_default);

    } else {
        Rectangle const leftKnob = {rectangle.x, rectangle.y, knobSize, knobSize};
        Rectangle const rightKnob = {ssize_t(rectangle.x + rectangle.w - knobSize), rectangle.y, knobSize, knobSize};

        Rectangle const slidKnob = {rectangle.x + knobSize + int(progress * (rectangle.w - 3 * knobSize) + 0.5f),
                                    rectangle.y,
                                    knobSize,
                                    knobSize};

        painter.fillRect(leftKnob, Color::background);
        painter.fillRect(rightKnob, Color::background);
        painter.fillRect(slidKnob, Color::background);

        painter.drawRect(leftKnob, Bevel::button_default);
        painter.drawRect(rightKnob, Bevel::button_default);
        painter.drawRect(slidKnob, Bevel::button_default);
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

    if (ev.type == SDL_MOUSEWHEEL) {
        scroll(ev.wheel.x + ev.wheel.y);
        return true;
    }

    auto const rectangle = actual_bounds;
    if (orientation.get(this) == Orientation::vertical) {
        Rectangle const topKnob = {rectangle.x, rectangle.y, knobSize, knobSize};
        Rectangle const botKnob = {rectangle.x, ssize_t(rectangle.y + rectangle.h - knobSize), knobSize, knobSize};

        Rectangle const knobArea = {
            rectangle.x,
            rectangle.y + knobSize,
            rectangle.w,
            rectangle.h - 2 * knobSize,
        };

        Rectangle const slidKnob = {
            rectangle.x,
            ssize_t(rectangle.y + knobSize + int(progress * (rectangle.h - 3 * knobSize) + 0.5f)),
            knobSize,
            knobSize};

        if (ev.type == SDL_MOUSEBUTTONUP)
            releaseMouse();

        if (hasMouseCaptured() and (ev.type == SDL_MOUSEMOTION)) {
            // move knob here!

            int const y = std::clamp<int>(ev.motion.y - knobArea.y - knobOffset, 0, knobArea.h - 1);

            float const p = float(y) / float(knobArea.h - 1);

            value.set(this, minval + range * p);

            return true;
        }

        if (is_clicked(topKnob, ev)) {
            value.set(this, std::clamp(val - clickperc * range, minval, maxval));
            return true;
        }
        if (is_clicked(botKnob, ev)) {
            value.set(this, std::clamp(val + clickperc * range, minval, maxval));
            return true;
        }
        if (is_clicked(slidKnob, ev)) {
            knobOffset = ev.button.y - slidKnob.y;
            captureMouse();
            return true;
        }
        if (is_clicked(knobArea, ev)) {
            if (ev.button.y < slidKnob.y)
                value.set(this, std::clamp(val - clickperc * range, minval, maxval));
            else
                value.set(this, std::clamp(val + clickperc * range, minval, maxval));
            return true;
        }
    } else {
        Rectangle const leftKnob = {rectangle.x, rectangle.y, knobSize, knobSize};
        Rectangle const rightKnob = {ssize_t(rectangle.x + rectangle.w - knobSize), rectangle.y, knobSize, knobSize};

        Rectangle const knobArea = {
            rectangle.x + knobSize,
            rectangle.y,
            rectangle.w - 2 * knobSize,
            rectangle.h,
        };

        Rectangle const slidKnob = {
            ssize_t(rectangle.x + knobSize + int(progress * (rectangle.w - 3 * knobSize) + 0.5f)),
            rectangle.y,
            knobSize,
            knobSize};

        if (ev.type == SDL_MOUSEBUTTONUP)
            releaseMouse();

        if (hasMouseCaptured() and (ev.type == SDL_MOUSEMOTION)) {
            // move knob here!

            int const y = std::clamp<int>(ev.motion.x - knobArea.x - knobOffset, 0, knobArea.w - 1);

            float const p = float(y) / float(knobArea.w - 1);

            value.set(this, minval + range * p);

            return true;
        }

        if (is_clicked(leftKnob, ev)) {
            value.set(this, std::clamp<int>(val - clickperc * range, minval, maxval));
            return true;
        }
        if (is_clicked(rightKnob, ev)) {
            value.set(this, std::clamp<int>(val + clickperc * range, minval, maxval));
            return true;
        }
        if (is_clicked(slidKnob, ev)) {
            knobOffset = ev.button.x - slidKnob.x;
            captureMouse();
            return true;
        }
        if (is_clicked(knobArea, ev)) {
            if (ev.button.x < slidKnob.x)
                value.set(this, std::clamp(val - clickperc * range, minval, maxval));
            else
                value.set(this, std::clamp(val + clickperc * range, minval, maxval));
            return true;
        }
    }

    return Widget::processEvent(ev);
}

SDL_SystemCursor ScrollBar::getCursor(const UIPoint &) const
{
    return SDL_SYSTEM_CURSOR_HAND;
}

void ScrollBar::scroll(float amount)
{
    value.set(this, std::clamp<float>(value.get(this) - amount, minimum.get(this), maximum.get(this)));
}

ScrollView::ScrollView()
{
    horizontal_bar = new ScrollBar();
    horizontal_bar->orientation.set(horizontal_bar, Orientation::horizontal);
    horizontal_bar->margins.set(horizontal_bar, UIMargin(0));

    vertical_bar = new ScrollBar();
    vertical_bar->orientation.set(vertical_bar, Orientation::vertical);
    vertical_bar->margins.set(vertical_bar, UIMargin(0));

    container = new Container();
    container->margins.set(container, UIMargin(0));

    // Scroll bars overlap the container, so
    // insert container first
    children.emplace_back(container);
    children.emplace_back(horizontal_bar);
    children.emplace_back(vertical_bar);
}

void ScrollView::layoutChildren(const Rectangle & fullArea)
{
    auto area = calculateChildArea(fullArea);

    auto childArea = area;

    auto const child_size = container->wanted_size_with_margins();

    size_t const extend_x = std::max<ssize_t>(0, child_size.w - childArea.w);
    size_t const extend_y = std::max<ssize_t>(0, child_size.h - childArea.h);

    horizontal_bar->maximum.set(this, extend_x);
    vertical_bar->maximum.set(this, extend_y);

    if (horizontal_bar->value.get(this) > horizontal_bar->maximum.get(this)) {
        horizontal_bar->value.set(this, extend_x);
    }

    if (vertical_bar->value.get(this) > vertical_bar->maximum.get(this)) {
        vertical_bar->value.set(this, extend_y);
    }

    childArea.x -= int(horizontal_bar->value.get(this) + 0.5f);
    childArea.y -= int(vertical_bar->value.get(this) + 0.5f);

    Rectangle child_rect = {childArea.x,
                            childArea.y,
                            std::max(childArea.w, child_size.w),
                            std::max(childArea.h, child_size.h)};

    container->layout(child_rect);

    vertical_bar->layout(Rectangle{
        ssize_t(area.x + area.w),
        area.y,
        horizontal_bar->wanted_size.w,
        area.h,
    });

    horizontal_bar->layout(Rectangle{
        area.x,
        ssize_t(area.y + area.h),
        area.w,
        vertical_bar->wanted_size.h,
    });
}

Rectangle ScrollView::calculateChildArea(Rectangle rect)
{
    rect.w -= vertical_bar->wanted_size.w;
    rect.h -= horizontal_bar->wanted_size.h;
    return rect;
}

UISize ScrollView::calculateWantedSize(IWidgetPainter const &)
{
    auto childSize = container->wanted_size;
    childSize.w += horizontal_bar->wanted_size.w;
    childSize.h += vertical_bar->wanted_size.h;
    return childSize;
}

void ScrollView::paintWidget(IWidgetPainter & painter, const Rectangle & rect)
{
    painter.drawRect(calculateChildArea(rect), Bevel::raised);
}

std::vector<std::unique_ptr<Widget>> & ScrollView::getChildContainer()
{
    return container->getChildContainer();
}
