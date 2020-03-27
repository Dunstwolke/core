#ifndef ENUMS_HPP
#define ENUMS_HPP

#include <cstdint>
#include <string>

/// combined enum containing all possible enumeration values
/// used in the UI system.
namespace UIEnum
{
	constexpr uint8_t none = 0;
	constexpr uint8_t left = 1;
	constexpr uint8_t center = 2;
	constexpr uint8_t right = 3;
	constexpr uint8_t top = 4;
	constexpr uint8_t middle = 5;
	constexpr uint8_t bottom = 6;
	constexpr uint8_t stretch = 7;
	constexpr uint8_t expand = 8;
	constexpr uint8_t _auto = 9;
	constexpr uint8_t yesno = 10;
	constexpr uint8_t truefalse = 11;
	constexpr uint8_t onoff = 12;
	constexpr uint8_t visible = 13;
	constexpr uint8_t hidden = 14;
	constexpr uint8_t collapsed = 15;
	constexpr uint8_t vertical = 16;
	constexpr uint8_t horizontal = 17;
	constexpr uint8_t sans = 18;
	constexpr uint8_t serif = 19;
	constexpr uint8_t monospace = 20;
	constexpr uint8_t percent = 21;
	constexpr uint8_t absolute = 22;
	constexpr uint8_t zoom = 23;
	constexpr uint8_t contain = 24;
	constexpr uint8_t cover = 25;
}

enum class UIWidget : uint8_t
{
	invalid = 0, // marks "end of children" in the binary format
	button = 1,
	label = 2,
	combobox = 3,
	treeview = 5,
	listbox = 7,
	picture = 9,
	textbox = 10,
	checkbox = 11,
	radiobutton = 12,
	scrollview = 13,
	scrollbar = 14,
	slider = 15,
	progressbar = 16,
	spinedit = 17,
	separator = 18,
	spacer = 19,
	panel = 20,
	container = 21,
	tab_layout = 250,
	canvas_layout = 251,
	flow_layout = 252,
	grid_layout = 253,
	dock_layout = 254,
	stack_layout = 255,
};

enum class UIProperty : uint8_t
{
	invalid = 0, // marks "end of properties" in the binary format
	horizontalAlignment = 1,
	verticalAlignment = 2,
	margins = 3,
	paddings = 4,
	dockSite = 6,
	visibility = 7,
	sizeHint = 8,
	fontFamily = 9,
	text = 10,
	minimum = 11,
	maximum = 12,
	value = 13,
	displayProgressStyle = 14,
	isChecked = 15,
	tabTitle = 16,
	selectedIndex = 17,
	columns = 18,
	rows = 19,
	left = 20,
	top = 21,
	enabled = 22,
	imageScaling = 23,
	image = 24,
	bindingContext = 25,
	childSource = 26,
	childTemplate = 27,
	hitTestVisible = 29,
	onClick = 30,
	orientation = 31,
	name = 32,
};

enum class UIType : uint8_t
{
	invalid = 0,
	integer = 1,
	number = 2,
	string = 3,
	enumeration = 4,
	margins = 5,
	color = 6,
	size = 7,
	point = 8,
	resource = 9,
	boolean = 10,
	sizelist = 11,
	object = 12,
	objectlist = 13,
	callback = 14,
};

enum class BooleanFormat : uint8_t
{
	truefalse = UIEnum::truefalse,
	yesno = UIEnum::yesno,
	onoff = UIEnum::onoff,
};

enum class VAlignment : uint8_t
{
	stretch = UIEnum::stretch,
	top = UIEnum::top,
	middle = UIEnum::middle,
	bottom = UIEnum::bottom,
};

enum class DockSite : uint8_t
{
	top = UIEnum::top,
	bottom = UIEnum::bottom,
	left = UIEnum::left,
	right = UIEnum::right,
};

enum class Visibility : uint8_t
{
	visible = UIEnum::visible,
	collapsed = UIEnum::collapsed,
	hidden = UIEnum::hidden,
};

enum class ImageScaling : uint8_t
{
	none = UIEnum::none,
	center = UIEnum::center,
	stretch = UIEnum::stretch,
	zoom = UIEnum::zoom,
	contain = UIEnum::contain,
	cover = UIEnum::cover,
};

enum class Orientation : uint8_t
{
	horizontal = UIEnum::horizontal,
	vertical = UIEnum::vertical,
};

enum class StackDirection : uint8_t
{
	vertical = UIEnum::vertical,
	horizontal = UIEnum::horizontal,
};

enum class HAlignment : uint8_t
{
	stretch = UIEnum::stretch,
	left = UIEnum::left,
	center = UIEnum::center,
	right = UIEnum::right,
};

enum class UIFont : uint8_t
{
	sans = UIEnum::sans,
	serif = UIEnum::serif,
	monospace = UIEnum::monospace,
};

enum class DisplayProgressStyle : uint8_t
{
	none = UIEnum::none,
	percent = UIEnum::percent,
	absolute = UIEnum::absolute,
};

UIType getPropertyType(UIProperty property);

std::string to_string(UIProperty property);
std::string to_string(UIWidget property);
std::string to_enum_string(uint8_t enumValue);
std::string to_string(UIType property);

#endif // ENUMS_HPP
