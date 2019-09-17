#include "enums.hpp"
#include <cassert>

UIType getPropertyType(UIProperty property)
{
	switch(property)
	{
		case UIProperty::horizontalAlignment: return UIType::enumeration;
		case UIProperty::verticalAlignment: return UIType::enumeration;
		case UIProperty::margins: return UIType::margins;
		case UIProperty::paddings: return UIType::margins;
		case UIProperty::stackDirection: return UIType::enumeration;
		case UIProperty::dockSite: return UIType::enumeration;
		case UIProperty::visibility: return UIType::enumeration;
		case UIProperty::sizeHint: return UIType::size;
		case UIProperty::fontFamily: return UIType::enumeration;
		case UIProperty::text: return UIType::string;
		case UIProperty::minimum: return UIType::number;
		case UIProperty::maximum: return UIType::number;
		case UIProperty::value: return UIType::number;
		case UIProperty::displayProgressStyle: return UIType::enumeration;
		case UIProperty::isChecked: return UIType::boolean;
		case UIProperty::tabTitle: return UIType::string;
		case UIProperty::selectedIndex: return UIType::integer;
		case UIProperty::columns: return UIType::sizelist;
		case UIProperty::rows: return UIType::sizelist;
		case UIProperty::left: return UIType::integer;
		case UIProperty::top: return UIType::integer;
		case UIProperty::enabled: return UIType::boolean;
		case UIProperty::imageScaling: return UIType::enumeration;
		case UIProperty::image: return UIType::resource;
		case UIProperty::bindingContext: return UIType::object;
		case UIProperty::childSource: return UIType::objectlist;
		case UIProperty::childTemplate: return UIType::resource;
		case UIProperty::toolTip: return UIType::string;
		case UIProperty::hitTestVisible: return UIType::boolean;
	}
	assert(false and "invalid property was passed to getPropertyType!");
}

std::string to_string(UIProperty property)
{
	switch(property)
	{
		case UIProperty::horizontalAlignment: return "horizontal-alignment";
		case UIProperty::verticalAlignment: return "vertical-alignment";
		case UIProperty::margins: return "margins";
		case UIProperty::paddings: return "paddings";
		case UIProperty::stackDirection: return "stack-direction";
		case UIProperty::dockSite: return "dock-site";
		case UIProperty::visibility: return "visibility";
		case UIProperty::sizeHint: return "size-hint";
		case UIProperty::fontFamily: return "font-family";
		case UIProperty::text: return "text";
		case UIProperty::minimum: return "minimum";
		case UIProperty::maximum: return "maximum";
		case UIProperty::value: return "value";
		case UIProperty::displayProgressStyle: return "display-progress-style";
		case UIProperty::isChecked: return "is-checked";
		case UIProperty::tabTitle: return "tab-title";
		case UIProperty::selectedIndex: return "selected-index";
		case UIProperty::columns: return "columns";
		case UIProperty::rows: return "rows";
		case UIProperty::left: return "left";
		case UIProperty::top: return "top";
		case UIProperty::enabled: return "enabled";
		case UIProperty::imageScaling: return "image-scaling";
		case UIProperty::image: return "image";
		case UIProperty::bindingContext: return "binding-context";
		case UIProperty::childSource: return "child-source";
		case UIProperty::childTemplate: return "child-template";
		case UIProperty::toolTip: return "tool-tip";
		case UIProperty::hitTestVisible: return "hit-test-visible";
	}
	return "property(" + std::to_string(int(property)) + ")";
}
std::string to_string(UIWidget widget)
{
	switch(widget)
	{
		case UIWidget::button: return "Button";
		case UIWidget::label: return "Label";
		case UIWidget::combobox: return "ComboBox";
		case UIWidget::treeviewitem: return "TreeViewItem";
		case UIWidget::treeview: return "TreeView";
		case UIWidget::listboxitem: return "ListBoxItem";
		case UIWidget::listbox: return "ListBox";
		case UIWidget::picture: return "Picture";
		case UIWidget::textbox: return "TextBox";
		case UIWidget::checkbox: return "CheckBox";
		case UIWidget::radiobutton: return "RadioButton";
		case UIWidget::scrollview: return "ScrollView";
		case UIWidget::scrollbar: return "ScrollBar";
		case UIWidget::slider: return "Slider";
		case UIWidget::progressbar: return "ProgressBar";
		case UIWidget::spinedit: return "SpinEdit";
		case UIWidget::separator: return "Separator";
		case UIWidget::spacer: return "Spacer";
		case UIWidget::panel: return "Panel";
		case UIWidget::tab_layout: return "TabLayout";
		case UIWidget::canvas_layout: return "CanvasLayout";
		case UIWidget::flow_layout: return "FlowLayout";
		case UIWidget::grid_layout: return "GridLayout";
		case UIWidget::dock_layout: return "DockLayout";
		case UIWidget::stack_layout: return "StackLayout";
	}
	return "widget(" + std::to_string(int(widget)) + ")";
}

std::string to_enum_string(uint8_t enumValue)
{
	switch(enumValue)
	{
		case 0: return "none";
		case 1: return "left";
		case 2: return "center";
		case 3: return "right";
		case 4: return "top";
		case 5: return "middle";
		case 6: return "bottom";
		case 7: return "stretch";
		case 8: return "expand";
		case 9: return "_auto";
		case 10: return "yesno";
		case 11: return "truefalse";
		case 12: return "onoff";
		case 13: return "visible";
		case 14: return "hidden";
		case 15: return "collapsed";
		case 16: return "vertical";
		case 17: return "horizontal";
		case 18: return "sans";
		case 19: return "serif";
		case 20: return "monospace";
		case 21: return "percent";
		case 22: return "absolute";
		case 23: return "zoom";
		case 24: return "contain";
		case 25: return "cover";
	}
	return "enum(" + std::to_string(int(enumValue)) + ")";
}

std::string to_string(UIType type)
{
	switch(type)
	{
		case UIType::invalid: return "invalid";
		case UIType::integer: return "integer";
		case UIType::number: return "number";
		case UIType::string: return "string";
		case UIType::enumeration: return "enumeration";
		case UIType::margins: return "margins";
		case UIType::color: return "color";
		case UIType::size: return "size";
		case UIType::point: return "point";
		case UIType::resource: return "resource";
		case UIType::boolean: return "boolean";
		case UIType::sizelist: return "sizelist";
		case UIType::object: return "object";
		case UIType::objectlist: return "objectlist";
	}
	return "type(" + std::to_string(int(type)) + ")";
}

