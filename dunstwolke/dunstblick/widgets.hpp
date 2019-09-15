#ifndef WIDGETS_HPP
#define WIDGETS_HPP

#include "widget.hpp"

struct Spacer : WidgetIs<UIWidget::spacer>
{
    void paintWidget(const SDL_Rect &rectangle) override;
};

struct Button : WidgetIs<UIWidget::button>
{
    void paintWidget(const SDL_Rect &rectangle) override;
};

struct Label : WidgetIs<UIWidget::label>
{
    property<std::string> text = std::string("");
    property<UIFont> font = UIFont::sans;

    explicit Label();

    void paintWidget(const SDL_Rect &rectangle) override;

    SDL_Size calculateWantedSize() override;
};

struct PlaceholderWidget : WidgetIs<UIWidget::spacer>
{
    SDL_Size calculateWantedSize() override;

    void paintWidget(const SDL_Rect &rectangle) override;
};

#define ComboBox PlaceholderWidget
#define TreeViewItem PlaceholderWidget
#define TreeView PlaceholderWidget
#define ListBoxItem PlaceholderWidget
#define ListBox PlaceholderWidget

struct Picture : WidgetIs<UIWidget::picture>
{
    property<UIResourceID> image;
		property<ImageScaling> scaling = ImageScaling::stretch;

    void paintWidget(const SDL_Rect &rectangle) override;

    SDL_Size calculateWantedSize() override;
};

#define TextBox PlaceholderWidget

struct CheckBox : WidgetIs<UIWidget::checkbox>
{
    property<bool> isChecked = false;

    CheckBox();

    SDL_Size calculateWantedSize() override;

    void paintWidget(const SDL_Rect &rectangle) override;
};


struct RadioButton : WidgetIs<UIWidget::checkbox>
{
    property<bool> isChecked = false;

    RadioButton();

    SDL_Size calculateWantedSize() override;

    void paintWidget(const SDL_Rect &rectangle) override;
};

#define ScrollView PlaceholderWidget
#define ScrollBar PlaceholderWidget

struct Slider : WidgetIs<UIWidget::progressbar>
{
	property<float> minimum = 0.0f;
    property<float> maximum = 100.0f;
    property<float> value = 0.0f;

	bool is_taking_input = false;

    SDL_Size calculateWantedSize() override;

    void paintWidget(const SDL_Rect &rectangle) override;

	bool processEvent(SDL_Event const & ev) override;
};

struct ProgressBar : WidgetIs<UIWidget::progressbar>
{
    property<float> minimum = 0.0f;
    property<float> maximum = 100.0f;
    property<float> value = 0.0f;
    property<DisplayProgressStyle> displayProgress = DisplayProgressStyle::percent;

    SDL_Size calculateWantedSize() override;

    void paintWidget(const SDL_Rect &rectangle) override;
};

#define SpinEdit PlaceholderWidget

struct Separator : WidgetIs<UIWidget::separator>
{
    SDL_Size calculateWantedSize() override;

    void paintWidget(const SDL_Rect &rectangle) override;
};


struct Panel : WidgetIs<UIWidget::panel>
{
    void paintWidget(const SDL_Rect &rectangle) override;
};


#endif // WIDGETS_HPP
