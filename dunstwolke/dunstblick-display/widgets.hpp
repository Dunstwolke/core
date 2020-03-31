#ifndef WIDGETS_HPP
#define WIDGETS_HPP

#include "widget.hpp"

struct Spacer : WidgetIs<UIWidget::spacer>
{
    Spacer();

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

struct Container : WidgetIs<UIWidget::container>
{
    Container();

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

struct ClickableWidget : Widget
{
    explicit ClickableWidget(UIWidget type);

    bool isKeyboardFocusable() const override;

    SDL_SystemCursor getCursor(UIPoint const &) const override;

    bool processEvent(const SDL_Event & event) override;

    virtual void onClick() = 0;
};

struct Button : ClickableWidget
{
    property<EventID> onClickEvent;

    Button();

    void onClick() override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

struct Label : WidgetIs<UIWidget::label>
{
    property<std::string> text = std::string("");
    property<UIFont> font = UIFont::sans;

    explicit Label();

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;

    UISize calculateWantedSize(IWidgetPainter const &) override;
};

struct PlaceholderWidget : WidgetIs<UIWidget::spacer>
{
    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

#define ComboBox PlaceholderWidget
// #define TreeViewItem PlaceholderWidget
#define TreeView PlaceholderWidget
// #define ListBoxItem PlaceholderWidget
#define ListBox PlaceholderWidget

struct Picture : WidgetIs<UIWidget::picture>
{
    property<UIResourceID> image;
    property<ImageScaling> scaling = ImageScaling::stretch;

    Picture();

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;

    UISize calculateWantedSize(IWidgetPainter const &) override;
};

#define TextBox PlaceholderWidget

struct CheckBox : ClickableWidget
{
    property<bool> isChecked = false;

    CheckBox();

    void onClick() override;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

struct RadioButton : ClickableWidget
{
    property<bool> isChecked = false;

    RadioButton();

    void onClick() override;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

struct ScrollBar : WidgetIs<UIWidget::scrollbar>
{
    int static constexpr knobSize = 24;

    property<float> minimum = 0.0f;
    property<float> maximum = 100.0f;
    property<float> value = 25.0f;
    property<Orientation> orientation = Orientation::horizontal;

    int knobOffset;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;

    bool processEvent(SDL_Event const & ev) override;

    bool isKeyboardFocusable() const override
    {
        return true;
    }

    SDL_SystemCursor getCursor(UIPoint const &) const override;

    void scroll(float amount);
};

struct ScrollView : WidgetIs<UIWidget::scrollview>
{
    ScrollBar horizontal_bar, vertical_bar;

    ScrollView();

    void layoutChildren(Rectangle const & childArea) override;

    Rectangle calculateChildArea(Rectangle rect);

    UISize calculateWantedSize(IWidgetPainter const &) override;

    Widget * hitTest(int ssx, int ssy) override;

    void paint(IWidgetPainter & painter) override;
    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;

    SDL_SystemCursor getCursor(UIPoint const &) const override;

    bool processEvent(SDL_Event const & ev) override;
};

struct Slider : WidgetIs<UIWidget::slider>
{
    property<float> minimum = 0.0f;
    property<float> maximum = 100.0f;
    property<float> value = 0.0f;
    property<Orientation> orientation = Orientation::horizontal;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;

    bool processEvent(SDL_Event const & ev) override;

    bool isKeyboardFocusable() const override
    {
        return true;
    }

    SDL_SystemCursor getCursor(UIPoint const &) const override
    {
        return SDL_SYSTEM_CURSOR_HAND;
    }
};

struct ProgressBar : WidgetIs<UIWidget::progressbar>
{
    property<float> minimum = 0.0f;
    property<float> maximum = 100.0f;
    property<float> value = 0.0f;
    property<DisplayProgressStyle> displayProgress = DisplayProgressStyle::percent;

    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

#define SpinEdit PlaceholderWidget

struct Separator : WidgetIs<UIWidget::separator>
{
    UISize calculateWantedSize(IWidgetPainter const &) override;

    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

struct Panel : WidgetIs<UIWidget::panel>
{
    void paintWidget(IWidgetPainter & painter, const Rectangle & rectangle) override;
};

#endif // WIDGETS_HPP
