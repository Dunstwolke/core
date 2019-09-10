#ifndef WIDGET_HPP
#define WIDGET_HPP

#include "enums.hpp"
#include "types.hpp"

#include "inputstream.hpp"
#include "rendercontext.hpp"

#include <vector>
#include <memory>
#include <variant>
#include <sdl2++/renderer>

// widget layouting algorithm:
// stage 1:
//   calculate bottom-to-top the wanted_size for each widget
// stage 2:
//   lay out top-to-bottom each widget into its parent container

struct Widget
{
public: // widget tree
    /// contains all child widgets
    std::vector<std::unique_ptr<Widget>> children;

public: // deserializable properties
    HAlignment horizontalAlignment = HAlignment::stretch;
    VAlignment verticalAlignment = VAlignment::stretch;
    Visibility visibility = Visibility::visible;
    UIMargin margins = UIMargin(0);
    UIMargin paddings = UIMargin(0);

public: // layouting and rendering
    /// the space the widget says it needs to have.
    /// this is a hint to each layouting algorithm to auto-size the widget
    /// accordingly.
    SDL_Size wanted_size;

    /// the position of the widget on the screen after layouting
    /// NOTE: this does not include the margins of the widget!
    SDL_Rect actual_bounds;

public:
    virtual ~Widget() = default;

    /// stage1: calculates recursively the wanted size of all widgets.
    void updateWantedSize();

    /// stage2: recursivly lays out this widget and all child widgets.
    /// @param bounds the rectangle this widget should reside in.
    ///        These bounds will be reduced by the margins of the widget.
    ///        the widget will be positioned according to its alignments into this layout
    void layout(SDL_Rect const & bounds);

    /// draws the widget
    void paint(RenderContext & context);

    /// returns the bounds of the widget with margins
    SDL_Rect bounds_with_margins() const;

    /// returns the wanted_size of the widget with margins added
    SDL_Size wanted_size_with_margins() const;

    /// deserializes a single property or throws a "not supported exception"
    virtual void setProperty(UIProperty property, UIValue value);

protected:
    /// stage1: calculates the space this widget wants to take.
    /// MUST refresh `wanted_size` field!
    /// the default is the maximum size of all its children combined
    virtual SDL_Size calculateWantedSize();

    /// stage2: recursively lays out all child elements to the widgets layout.
    /// the default layouting is "all children get their wanted size with alignment".
    /// note: this method should call layout(rect) on all its children!
    /// @param childArea the area where the children will be positioned in
    virtual void layoutChildren(SDL_Rect const & childArea);

    virtual void paintWidget(RenderContext & context, SDL_Rect const & rectangle) = 0;
};

#endif // WIDGET_HPP
