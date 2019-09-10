#include "widgets.hpp"

SDL_Size Spacer::calculateWantedSize()
{
    return sizeHint;
}

void Spacer::paintWidget(RenderContext &, const SDL_Rect &)
{

}

void Spacer::setProperty(UIProperty property, UIValue value)
{
    switch(property) {
    case UIProperty::sizeHint: sizeHint = std::get<SDL_Size>(value); break;
    default:
        return Widget::setProperty(property, value);
    }
}

void Button::paintWidget(RenderContext & context, const SDL_Rect &rectangle)
{
    context.renderer.setColor(0x80, 0x80, 0x80);
    context.renderer.fillRect(rectangle);

    context.renderer.setColor(0xFF, 0xFF, 0xFF);
    context.renderer.drawRect(rectangle);
}

Label::Label() : Widget()
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

void Label::setProperty(UIProperty property, UIValue value)
{
    switch(property) {
    case UIProperty::fontFamily: font = UIFont(std::get<uint8_t>(value)); break;
    case UIProperty::text:         text = std::get<std::string>(value); break;
    default:
        return Widget::setProperty(property, value);
    }
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
