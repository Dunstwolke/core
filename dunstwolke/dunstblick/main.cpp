#include <SDL.h>
#include <sdl2++/renderer>
#include <vector>

#include "widget.hpp"
#include "layouts.hpp"

#include "inputstream.hpp"

bool shutdown_app_requested = false;

[[noreturn]] void exit_sdl_error(char const * msg = nullptr) {
    fprintf(
        stderr,
        "%s: %s\n",
        (msg != nullptr) ? msg : "sdl error",
        SDL_GetError()
    );
    fflush(stdout);
    fflush(stderr);
    exit(1);
}

/// A color scheme for the UI system
struct ColorScheme
{
    UIColor background    = { 0x40, 0x40, 0x40 };

    UIColor borderDefault = { 0x00, 0x80, 0x00 };
    UIColor borderHovered = { 0x00, 0xC0, 0x00 };
    UIColor borderFocused = { 0x00, 0xFF, 0x00 };
};


ColorScheme const defaultColorScheme;

std::unique_ptr<Widget> root_widget;

struct DemoWidget : Widget
{
    int layer = 0;
    static inline int next_layer = 0;

    explicit DemoWidget() : layer(next_layer++) { }

    void paintWidget(sdl2::renderer & renderer, SDL_Rect const & rectangle) override
    {
        switch(layer % 3) {
        case 0: renderer.setColor(0xFF, 0x00, 0x00); break;
        case 1: renderer.setColor(0x00, 0xFF, 0x00); break;
        case 2: renderer.setColor(0x00, 0x00, 0xFF); break;
        }
        renderer.fillRect(rectangle);

        renderer.setColor(0xFF, 0xFF, 0xFF);
        renderer.drawRect(rectangle);
    }

    SDL_Size calculateWantedSize() override
    {
        return { 64, 64 };
    }
};


void paint(sdl2::renderer & renderer)
{
    auto const & scheme = defaultColorScheme;

    renderer.resetClipRect();
    assert(not renderer.isClipEnabled());

    renderer.setColor(scheme.background);
    renderer.clear();
    renderer.fillRect(SDL_Rect { 0, 0, 1280, 720 });

    if(root_widget)
        root_widget->paint(renderer);

    renderer.present();
}

void event(SDL_Event const & e)
{
    switch(e.type) {
    case SDL_QUIT:
        shutdown_app_requested = true;
        break;
    case SDL_KEYDOWN:
        if(e.key.keysym.sym == SDLK_ESCAPE)
            shutdown_app_requested = true;
        break;
    }
}

uint8_t const formData[] =
    "\xFF" // StackLayout
        "\x03" // 2 properties
            "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
            "\x04\x08\x08\x08\x08" // paddings, 8,8,8,8
            "\x05\x11" // direction = horizontal
        "\x04" // 4 child objects
            "\x00" // spacer widget
                "\x03" // 3 properties
                    "\x01\x01" // horizontal alignment = left
                    "\x02\x04" // vertical alignment = top
                    "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
                "\x00" // 0 children
            "\x00" // spacer widget
                "\x03" // 3 properties
                    "\x01\x02" // horizontal alignment = center
                    "\x02\x05" // vertical alignment = middle
                    "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
                "\x00" // 0 children
            "\x00" // spacer widget
                "\x03" // 3 properties
                    "\x01\x03" // horizontal alignment = right
                    "\x02\x06" // vertical alignment = bottom
                    "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
                "\x00" // 0 children
            "\x00" // spacer widget
                "\x03" // 3 properties
                    "\x01\x07" // horizontal alignment = stretch
                    "\x02\x07" // vertical alignment = stretch
                    "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
                "\x00" // 0 children
;

std::unique_ptr<Widget> deserialize_stream(InputStream & stream)
{
    auto const widgetType = stream.read_enum<UIWidget>();

    std::unique_ptr<Widget> widget;
    switch(widgetType)
    {
    case UIWidget::spacer: widget = std::make_unique<DemoWidget>(); break;


    case UIWidget::dock_layout: widget = std::make_unique<DockLayout>(); break;
    case UIWidget::stack_layout: widget = std::make_unique<StackLayout>(); break;
    default:
        assert(false and "not implemented yet!");
    }
    assert(widget);

    auto const propertyCount = stream.read_uint();
    for(size_t i = 0; i < propertyCount; i++)
    {
        auto const property = stream.read_enum<UIProperty>();
        widget->deserialize_property(property, stream);
    }

    auto const childCount = stream.read_uint();
    widget->children.resize(childCount);
    for(size_t i = 0; i < childCount; i++)
    {
         widget->children[i] = deserialize_stream(stream);
    }

    return widget;
}

int main()
{
    if(SDL_Init(SDL_INIT_EVERYTHING) < 0) {
        exit_sdl_error();
    }
    atexit(SDL_Quit);

    SDL_Window * window = SDL_CreateWindow(
        "DunstBlick Frontend",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        1280, 720,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );
    if(window == nullptr) {
        exit_sdl_error();
    }

    sdl2::renderer renderer { window };
    renderer.setBlendMode(SDL_BLENDMODE_BLEND); // enable alpha blend

    InputStream formStream(formData);

    root_widget = deserialize_stream(formStream);

    while(not shutdown_app_requested)
    {
        SDL_Event e;
        while(SDL_PollEvent(&e))
        {
            event(e);
        }

        SDL_Rect screen_rect = { 0, 0, -1, -1 };
        SDL_GetWindowSize(window, &screen_rect.w, &screen_rect.h);

        root_widget->updateWantedSize();
        root_widget->layout(screen_rect);

        paint(renderer);
        SDL_Delay(16);
    }

    SDL_DestroyWindow(window);

    return 0;
}
