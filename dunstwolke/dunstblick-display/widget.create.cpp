#include "widgets.hpp"
#include "layouts.hpp"
#include <stdexcept>

std::unique_ptr<Widget> Widget::create(UIWidget id)
{
	switch(id)
	{
		case UIWidget::invalid: throw std::runtime_error("cannot instantiate widget of type 'invalid'");
		case UIWidget::button: return std::make_unique<Button>();
		case UIWidget::label: return std::make_unique<Label>();
		case UIWidget::combobox: return std::make_unique<ComboBox>();
		case UIWidget::treeview: return std::make_unique<TreeView>();
		case UIWidget::listbox: return std::make_unique<ListBox>();
		case UIWidget::picture: return std::make_unique<Picture>();
		case UIWidget::textbox: return std::make_unique<TextBox>();
		case UIWidget::checkbox: return std::make_unique<CheckBox>();
		case UIWidget::radiobutton: return std::make_unique<RadioButton>();
		case UIWidget::scrollview: return std::make_unique<ScrollView>();
		case UIWidget::scrollbar: return std::make_unique<ScrollBar>();
		case UIWidget::slider: return std::make_unique<Slider>();
		case UIWidget::progressbar: return std::make_unique<ProgressBar>();
		case UIWidget::spinedit: return std::make_unique<SpinEdit>();
		case UIWidget::separator: return std::make_unique<Separator>();
		case UIWidget::spacer: return std::make_unique<Spacer>();
		case UIWidget::panel: return std::make_unique<Panel>();
		case UIWidget::tab_layout: return std::make_unique<TabLayout>();
		case UIWidget::canvas_layout: return std::make_unique<CanvasLayout>();
		case UIWidget::flow_layout: return std::make_unique<FlowLayout>();
		case UIWidget::grid_layout: return std::make_unique<GridLayout>();
		case UIWidget::dock_layout: return std::make_unique<DockLayout>();
		case UIWidget::stack_layout: return std::make_unique<StackLayout>();
	}
	assert(false and "invalid widget type was passed to Widget::create()!");
}
