#include "widgets.hpp"

SDL_Size Spacer::calculateWantedSize()
{
    return sizeHint;
}

void Spacer::paintWidget(RenderContext &, const SDL_Rect &)
{

}

void Button::paintWidget(RenderContext & context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0x80, 0x80, 0x80);
    context.renderer.fillRect(rectangle);

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawRect(rectangle);
}

Label::Label()
{
    margins = UIMargin(8);
    horizontalAlignment = HAlignment::center;
    verticalAlignment = VAlignment::middle;
}

void Label::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    auto & fc = RenderContext::current().getFont(font);
    auto * tex = fc.render(text);

    context.renderer.copy(tex, rectangle); // stretch for now...
}

SDL_Size Label::calculateWantedSize()
{
    auto & fc = RenderContext::current().getFont(font);
    auto * tex = fc.render(text);
    if(not tex)
        return { 0, TTF_FontHeight(fc.font.get()) };
    SDL_Size size;
    SDL_QueryTexture(tex, nullptr, nullptr, &size.w, &size.h);
    return size;
}

SDL_Size PlaceholderWidget::calculateWantedSize()
{
    return { 32, 32 };
}

void PlaceholderWidget::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0xFF, 0x00, 0xFF);
    context.renderer.fillRect(rectangle);

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawLine(rectangle.x, rectangle.y, rectangle.x + rectangle.w, rectangle.y + rectangle.h);
    context.renderer.drawLine(rectangle.x + rectangle.w, rectangle.y, rectangle.x, rectangle.y + rectangle.h);
    context.renderer.drawRect(rectangle);
}

void Panel::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0x30, 0x00, 0x30);
    context.renderer.fillRect(rectangle);

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawRect(rectangle);
}

SDL_Size Separator::calculateWantedSize()
{
    return { 5, 5 };
}

void Separator::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    if(rectangle.w > rectangle.h)
    {
        int y = rectangle.y + rectangle.h / 2;
        context.renderer.drawLine(rectangle.x, y, rectangle.x + rectangle.w, y);
    }
    else
    {
        int x = rectangle.x + rectangle.w / 2;
        context.renderer.drawLine(x, rectangle.y, x, rectangle.y + rectangle.h);
    }
}

SDL_Size ProgressBar::calculateWantedSize()
{
    return { 256, 32 };
}

void ProgressBar::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0x30, 0x30, 0x30);
    context.renderer.fillRect(rectangle);

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawRect(rectangle);

    SDL_Rect progressArea = {
        rectangle.x + 1,
        rectangle.y + 1,
        int((value - minimum) * float(rectangle.w - 2) / (maximum - minimum) + 0.5f),
        rectangle.h - 2
    };

    context.renderer.setColor(0x00, 0x00, 0xFF);
    context.renderer.fillRect(progressArea);

    std::string caption;
    switch(displayProgress)
    {
    case DisplayProgressStyle::none:
        caption = "";
        break;
    case DisplayProgressStyle::percent:
        caption = std::to_string(int(100.0f * (value - minimum) / (maximum - minimum) + 0.5f)) + "%";
        break;
    case DisplayProgressStyle::absolute:
        caption = std::to_string(int(value + 0.5f));
        break;
    }
    if(not caption.empty())
    {
        auto * tex = context.getFont(UIFont::sans).render(caption);

        int w,h;
        SDL_QueryTexture(tex, nullptr, nullptr, &w, &h);
        SDL_Rect label = {
            rectangle.x + (rectangle.w - w) / 2,
            rectangle.y + (rectangle.h - h) / 2,
            w, h
        };
        context.renderer.copy(tex, label);
    }
}

CheckBox::CheckBox()
{
    horizontalAlignment = HAlignment::left;
    verticalAlignment = VAlignment::middle;
}

SDL_Size CheckBox::calculateWantedSize()
{
    return { 32, 32 };
}

void CheckBox::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0x30, 0x30, 0x30);
    context.renderer.fillRect(rectangle);

    if(isChecked)
        context.renderer.setColor(0xD0, 0xD0, 0xD0);
    else
        context.renderer.setColor(0x40, 0x40, 0x40);

    context.renderer.fillRect({
        rectangle.x + 6,
        rectangle.y + 6,
        rectangle.w - 12,
        rectangle.h - 12,
    });

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawRect(rectangle);
}

RadioButton::RadioButton()
{
    horizontalAlignment = HAlignment::left;
    verticalAlignment = VAlignment::middle;
}

SDL_Size RadioButton::calculateWantedSize()
{
    return { 32, 32 };
}

void RadioButton::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    int centerX = rectangle.x + rectangle.w / 2;
    int centerY = rectangle.y + rectangle.h / 2;
    int radiusA = std::min(rectangle.w, rectangle.h) / 2 - 1;
    int radiusB = radiusA - 6;

    SDL_Point circleA[37], circleB[37];
    for(int i = 0; i <= 36; i++)
    {
        circleA[i].x = int(centerX + radiusA * sin(M_PI * i / 18.0));
        circleA[i].y = int(centerY + radiusA * cos(M_PI * i / 18.0));

        circleB[i].x = int(centerX + radiusB * sin(M_PI * i / 18.0));
        circleB[i].y = int(centerY + radiusB * cos(M_PI * i / 18.0));
    }

    if(isChecked)
        context.renderer.setColor(0xD0, 0xD0, 0xD0);
    else
        context.renderer.setColor(0x40, 0x40, 0x40);

    context.renderer.drawLines(circleB, 36);

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawLines(circleA, 36);
}

SDL_Size Slider::calculateWantedSize()
{
    return { 32, 32 };
}

void Slider::paintWidget(RenderContext &context, const SDL_Rect &rectangle)
{
    int const knobThick = 12;

    if(rectangle.w > rectangle.h)
    {
        // horizontal slider

        int y = rectangle.y + rectangle.h / 2;

        context.renderer.setColor(0xFF, 0xFF, 0xFF);
        context.renderer.drawLine(
            rectangle.x + knobThick / 2,
            y,
            rectangle.x + rectangle.w - knobThick / 2,
            y
        );

        SDL_Rect knob {
            rectangle.x + knobThick / 2 + int((rectangle.w - knobThick) * (value - minimum) / (maximum - minimum) + 0.5f),
            rectangle.y,
            knobThick,
            rectangle.h
        };

        context.renderer.setColor(0xC0, 0xC0, 0xC0);
        context.renderer.fillRect(knob);

        context.renderer.setColor(0xFF, 0xFF, 0xFF);
        context.renderer.drawRect(knob);
    }
    else
    {
        // vertical slider

        int x = rectangle.x + rectangle.w / 2;

        context.renderer.setColor(0xFF, 0xFF, 0xFF);
        context.renderer.drawLine(
            x,
            rectangle.y + knobThick / 2,
            x,
            rectangle.y + rectangle.h - knobThick / 2
        );

        SDL_Rect knob {
            rectangle.x,
            rectangle.y + knobThick / 2 + int((rectangle.h - knobThick) * (value - minimum) / (maximum - minimum) + 0.5f),
            rectangle.w,
            knobThick,
        };

        context.renderer.setColor(0xC0, 0xC0, 0xC0);
        context.renderer.fillRect(knob);

        context.renderer.setColor(0xFF, 0xFF, 0xFF);
        context.renderer.drawRect(knob);
    }
}
