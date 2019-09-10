#ifndef WIDGETS_HPP
#define WIDGETS_HPP

#include "widget.hpp"

struct Spacer : Widget
{
    SDL_Size sizeHint = { 0, 0 };

    SDL_Size calculateWantedSize() override;

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;

    void setProperty(UIProperty property, UIValue value) override;
};

struct Button : Widget
{
    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;
};

struct Label : Widget
{
    std::string text = "";
    UIFont font = UIFont::sans;

    explicit Label();

    void paintWidget(RenderContext & context, const SDL_Rect &rectangle) override;

    SDL_Size calculateWantedSize() override;

    void setProperty(UIProperty property, UIValue value) override;
};

struct PlaceholderWidget : Widget
{
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
#define ProgressBar PlaceholderWidget
#define SpinEdit PlaceholderWidget
#define Separator PlaceholderWidget

#define CanvasLayout StackLayout
#define FlowLayout StackLayout
#define GridLayout StackLayout

#endif // WIDGETS_HPP
