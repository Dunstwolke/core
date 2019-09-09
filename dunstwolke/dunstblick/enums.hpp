#ifndef ENUMS_HPP
#define ENUMS_HPP

#include <cstdint>

/// combined enum containing all possible enumeration values
/// used in the UI system.
namespace UIEnum
{
    constexpr uint8_t none       = 0;  // ?
    constexpr uint8_t left       = 1;  // h-alignment
    constexpr uint8_t center     = 2;  // h-alignment
    constexpr uint8_t right      = 3;  // h-alignment
    constexpr uint8_t top        = 4;  // v-alignment
    constexpr uint8_t middle     = 5;  // v-alignment
    constexpr uint8_t bottom     = 6;  // v-alignment
    constexpr uint8_t stretch    = 7;  // h-alignment, v-alignment
    constexpr uint8_t expand     = 8;  // column-size, row-size
    constexpr uint8_t _auto      = 9;  // column-size, row-size
    constexpr uint8_t yesno      = 10; // boolean format
    constexpr uint8_t truefalse  = 11; // boolean format
    constexpr uint8_t onoff      = 12; // boolean format
    constexpr uint8_t visible    = 13; // visibility
    constexpr uint8_t hidden     = 14; // visibility
    constexpr uint8_t collapsed  = 15; // visibility
    constexpr uint8_t vertical   = 16; // stackdirection
    constexpr uint8_t horizontal = 17; // stackdirection
    constexpr uint8_t sans       = 18; // uifont
    constexpr uint8_t serif      = 19; // uifont
    constexpr uint8_t monospace  = 20; // uifont
};

enum class UIWidget : uint8_t
{
    spacer        = 0,
    button        = 1,
    label         = 2,
    combobox      = 3,
    treeviewitem  = 4,
    treeview      = 5,
    listboxitem   = 6,
    listbox       = 7,
    drawing       = 8,
    picture       = 9,
    textbox       = 10,
    checkbox      = 11,
    radiobutton   = 12,
    scrollview    = 13,
    scrollbar     = 14,
    slider        = 15,
    progressbar   = 16,
    spinedit      = 17,
    separator     = 18,

    // widgets go here ↑
    // layouts go here ↓

    canvas_layout = 251,
    flow_layout   = 252,
    grid_layout   = 253,
    dock_layout   = 254,
    stack_layout  = 255,
};

enum class UIProperty : uint8_t
{
    invalid = 0,
    horizontalAlignment = 1,
    verticalAlignment = 2,
    margins = 3,
    paddings = 4,
    stackDirection = 5,
    dockSites = 6,
    visibility = 7,
    sizeHint = 8,
    fontFamility = 9,
    text = 10,

    // MAXMIMUM ALLOWED VALUE IS 127!
    // upper bit is used for marking value bindings
};

enum class UIType : uint8_t
{
    invalid     = 0,
    integer     = 1,
    number      = 2,
    string      = 3,
    enumeration = 4,
    margins     = 5,
    color       = 6,
    size        = 7,
    point       = 8,
    resource    = 9,
};

enum class UIFont : uint8_t
{
    sans = UIEnum::sans,
    serif = UIEnum::serif,
    monospace = UIEnum::monospace,
};

enum class HAlignment : uint8_t
{
    stretch = UIEnum::stretch,
    left = UIEnum::left,
    center = UIEnum::center,
    right = UIEnum::right,
};

enum class VAlignment : uint8_t
{
    stretch = UIEnum::stretch,
    top = UIEnum::top,
    middle = UIEnum::middle,
    bottom = UIEnum::bottom,
};

enum class Visibility : uint8_t
{
    visible   = UIEnum::visible,   ///< visible
    collapsed = UIEnum::collapsed, ///< not visible, also ignored in layouting
    hidden    = UIEnum::hidden,    ///< not visible, but will be lay out.
};

enum class StackDirection : uint8_t
{
    vertical   = UIEnum::vertical,   ///< vertical stacking is applied
    horizontal = UIEnum::horizontal, ///< horizontal stacking is applied
};

enum class DockSite : uint8_t
{
    top    = UIEnum::top,    ///< the widget will dock on the upper side
    bottom = UIEnum::bottom, ///< the widget will dock on the lower side
    left   = UIEnum::left,   ///< the widget will dock on the left side
    right  = UIEnum::right,  ///< the widget will dock on the right side
};

#endif // ENUMS_HPP
