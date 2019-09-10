#ifndef WIDGETS_HPP
#define WIDGETS_HPP

#include "widget.hpp"

struct Spacer : WidgetIs<UIWidget::spacer>
{
    property<SDL_Size> sizeHint = SDL_Size { 0, 0 };

    SDL_Size calculateWantedSize() override;

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

struct Button : WidgetIs<UIWidget::button>
{
    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

struct Label : WidgetIs<UIWidget::label>
{
    property<std::string> text = std::string("");
    property<UIFont> font = UIFont::sans;

    explicit Label();

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;

    SDL_Size calculateWantedSize() override;
};

struct PlaceholderWidget : WidgetIs<UIWidget::spacer>
{
    SDL_Size calculateWantedSize() override;

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

#define ComboBox PlaceholderWidget
#define TreeViewItem PlaceholderWidget
#define TreeView PlaceholderWidget
#define ListBoxItem PlaceholderWidget
#define ListBox PlaceholderWidget
#define Drawing PlaceholderWidget
#define Picture PlaceholderWidget
#define TextBox PlaceholderWidget
#define CheckBox PlaceholderWidget
#define RadioButton PlaceholderWidget
#define ScrollView PlaceholderWidget
#define ScrollBar PlaceholderWidget
#define Slider PlaceholderWidget

struct ProgressBar : WidgetIs<UIWidget::progressbar>
{
    property<float> minimum = 0.0f;
    property<float> maximum = 100.0f;
    property<float> value = 0.0f;
    property<DisplayProgressStyle> displayProgress = DisplayProgressStyle::percent;

    SDL_Size calculateWantedSize() override;

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

#define SpinEdit PlaceholderWidget

struct Separator : WidgetIs<UIWidget::separator>
{
    SDL_Size calculateWantedSize() override;

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};


struct Panel : WidgetIs<UIWidget::panel>
{
    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

#define CanvasLayout StackLayout
#define FlowLayout StackLayout
#define GridLayout StackLayout

#endif // WIDGETS_HPP
