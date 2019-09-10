#include <SDL.h>
#include <sdl2++/renderer>
#include <vector>
#include <filesystem>

#include "widget.hpp"
#include "layouts.hpp"
#include "widgets.hpp"

#include "inputstream.hpp"

#include "layoutparser.hpp"

static bool shutdown_app_requested = false;

[[noreturn]] static void exit_sdl_error(char const * msg = nullptr) {
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


static ColorScheme const defaultColorScheme;

static std::unique_ptr<Widget> root_widget;

struct DemoWidget : Widget
{
    int layer = 0;
    static inline int next_layer = 0;

    explicit DemoWidget() : layer(next_layer++) { }

    void paintWidget(RenderContext & context, SDL_Rect const & rectangle) override
    {
        switch(layer % 3) {
        case 0: context.renderer.setColor(0xFF, 0x00, 0x00); break;
        case 1: context.renderer.setColor(0x00, 0xFF, 0x00); break;
        case 2: context.renderer.setColor(0x00, 0x00, 0xFF); break;
        }
        context.renderer.fillRect(rectangle);

        context.renderer.setColor(0xFF, 0xFF, 0xFF);
        context.renderer.drawRect(rectangle);
    }

    SDL_Size calculateWantedSize() override
    {
        return { 64, 64 };
    }
};


static void paint(RenderContext & context)
{
    context.renderer.resetClipRect();
    assert(not context.renderer.isClipEnabled());

    context.renderer.setColor(0x00, 0x00, 0x00, 0xFF);
    context.renderer.fillRect(context.renderer.getViewport());

    if(root_widget)
        root_widget->paint(context);

    context.renderer.present();
}

static void event(SDL_Event const & e)
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
        "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
        "\x04\x08\x08\x08\x08" // paddings, 8,8,8,8
        "\x05\x11" // direction = horizontal
        "\x00" // end of properties
        "\x01" // button widget
            "\x01\x01" // horizontal alignment = left
            "\x02\x04" // vertical alignment = top
            "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
            "\x00" // end of properties
            "\x02" // label
                "\x09\x12" // font family =
                "\x0A\x05Upper" // text = "Upper"
                "\x00" // 0 end of properties
                "\x00" // 0 end of children
            "\x00" // end of children
        "\x01" // spacer widget
            "\x01\x02" // horizontal alignment = center
            "\x02\x05" // vertical alignment = middle
            "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
            "\x00" // 0 end of properties
            "\x02" // label
                "\x09\x12" // font family =
                "\x0A\x06Middle" // text = "Middle"
                "\x00" // 0 end of properties
                "\x00" // 0 end of children
            "\x00" // 0 end of children
        "\x01" // spacer widget
            "\x01\x03" // horizontal alignment = right
            "\x02\x06" // vertical alignment = bottom
            "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
            "\x00" // 0 end of properties
            "\x02" // label
                "\x09\x12" // font family =
                "\x0A\x05Lower" // text = "Lower"
                "\x00" // 0 end of properties
                "\x00" // 0 end of children
            "\x00" // 0 end of children
        "\x01" // spacer widget
            "\x01\x07" // horizontal alignment = stretch
            "\x02\x07" // vertical alignment = stretch
            "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
            "\x00" // 0 end of properties
            "\x02" // label
                "\x09\x12" // font family =
                "\x0A\x07Stretch" // text = "Stretch"
                "\x00" // end of properties
                "\x00" // end of children
            "\x00" // end of children
        "\x01" // spacer widget
            "\x01\x07" // horizontal alignment = stretch
            "\x02\x07" // vertical alignment = stretch
            "\x03\x10\x10\x10\x10" // margins, 16,16,16,16
            "\x00" // 0 end of properties
            "\x02" // label
                "\x09\x12" // font family =
                "\x0A\x0AMulti\nLine" // text = "Multi\nLine"
                "\x00" // end of properties
                "\x00" // end of children
            "\x00" // end of children
    "\x00" // end of children

;

UIType getPropertyType(UIProperty property)
{
    switch(property)
    {
    case UIProperty::horizontalAlignment:
    case UIProperty::verticalAlignment:
    case UIProperty::stackDirection:
    case UIProperty::dockSites:
    case UIProperty::visibility:
    case UIProperty::fontFamily:
        return UIType::enumeration;

    case UIProperty::margins:
    case UIProperty::paddings:
        return UIType::margins;

    case UIProperty::sizeHint:
        return UIType::size;

    case UIProperty::text:
        return UIType::string;

    default: assert(false and "property type not in table yet!");
    }
}

UIValue deserialize_value(UIType type, InputStream & stream)
{
    switch(type)
    {
    case UIType::enumeration:
        return stream.read_byte();

    case UIType::integer:
        return gsl::narrow<int>(stream.read_uint());

    case UIType::size:
    {
        SDL_Size size;
        size.w = gsl::narrow<int>(stream.read_uint());
        size.h = gsl::narrow<int>(stream.read_uint());
        return size;
    }

    case UIType::string:
        return std::string(stream.read_string());

    case UIType::margins:
    {
        UIMargin margin(0);
        margin.left = gsl::narrow<int>(stream.read_uint());
        margin.top = gsl::narrow<int>(stream.read_uint());
        margin.right = gsl::narrow<int>(stream.read_uint());
        margin.bottom = gsl::narrow<int>(stream.read_uint());
        return margin;
    }


    }
    assert(false and "property type not in table yet!");
}

std::unique_ptr<Widget> deserialize_widget(UIWidget widgetType, InputStream & stream)
{
    std::unique_ptr<Widget> widget;
    switch(widgetType)
    {
    case UIWidget::spacer: widget = std::make_unique<Spacer>(); break;
    case UIWidget::button: widget = std::make_unique<Button>(); break;
    case UIWidget::label:  widget = std::make_unique<Label>(); break;


    case UIWidget::dock_layout: widget = std::make_unique<DockLayout>(); break;
    case UIWidget::stack_layout: widget = std::make_unique<StackLayout>(); break;
    default:
        assert(false and "not implemented yet!");
    }
    assert(widget);

    UIProperty property;
    do
    {
        property = stream.read_enum<UIProperty>();
        if(property != UIProperty::invalid)
        {
            auto const value = deserialize_value(getPropertyType(property), stream);
            widget->setProperty(property, value);
        }
    } while(property != UIProperty::invalid);

    UIWidget childType;
    do
    {
        childType = stream.read_enum<UIWidget>();
        if(childType != UIWidget::invalid)
            widget->children.emplace_back(deserialize_widget(childType, stream));
    } while(childType != UIWidget::invalid);

    return widget;
}

std::unique_ptr<Widget> deserialize_widget(InputStream & stream)
{
    auto const widgetType = stream.read_enum<UIWidget>();
    return deserialize_widget(widgetType, stream);
}

#include <fstream>

int main()
{
    printf("cwd = %s\n", std::filesystem::current_path().c_str());
    fflush(stdout);

    std::ifstream input_src("./dunstblick/development.uit");

    std::ofstream output_dst("/tmp/development.ui");

    std::ofstream output_cmp("/tmp/development.ui.orig");
    output_cmp.write((char const *)formData, sizeof(formData) - 1);

    LayoutParser layout_parser;
    layout_parser.compile(input_src, output_dst);

    return 0;

    if(SDL_Init(SDL_INIT_EVERYTHING) < 0) {
        exit_sdl_error();
    }
    atexit(SDL_Quit);

    if(TTF_Init() < 0) {
        exit_sdl_error();
    }
    atexit(TTF_Quit);

    SDL_Window * window = SDL_CreateWindow(
        "DunstBlick Frontend",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        1280, 720,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );
    if(window == nullptr) {
        exit_sdl_error();
    }

    RenderContext render_context {
        sdl2::renderer { window },
        "./fonts/Roboto-Regular.ttf",
        "./fonts/CrimsonPro-Regular.ttf",
        "./fonts/SourceCodePro-Regular.ttf"
    };

    RenderContext::setCurrent(&render_context);

    render_context.renderer.setBlendMode(SDL_BLENDMODE_BLEND); // enable alpha blend

    InputStream formStream(formData);

    root_widget = deserialize_widget(formStream);

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

        paint(render_context);
        SDL_Delay(16);
    }

    SDL_DestroyWindow(window);

    return 0;
}
