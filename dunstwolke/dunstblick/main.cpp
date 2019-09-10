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
    case UIProperty::displayProgressStyle:
        return UIType::enumeration;

    case UIProperty::margins:
    case UIProperty::paddings:
        return UIType::margins;

    case UIProperty::sizeHint:
        return UIType::size;

    case UIProperty::text:
        return UIType::string;

    case UIProperty::minimum:
    case UIProperty::maximum:
    case UIProperty::value:
        return UIType::number;

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

    case UIType::number:
        return gsl::narrow<float>(stream.read_float());

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
    case UIWidget::combobox:  widget = std::make_unique<ComboBox>(); break;
    case UIWidget::treeviewitem:  widget = std::make_unique<TreeViewItem>(); break;
    case UIWidget::treeview:  widget = std::make_unique<TreeView>(); break;
    case UIWidget::listboxitem:  widget = std::make_unique<ListBoxItem>(); break;
    case UIWidget::listbox:  widget = std::make_unique<ListBox>(); break;
    case UIWidget::drawing:  widget = std::make_unique<Drawing>(); break;
    case UIWidget::picture:  widget = std::make_unique<Picture>(); break;
    case UIWidget::textbox:  widget = std::make_unique<TextBox>(); break;
    case UIWidget::checkbox:  widget = std::make_unique<CheckBox>(); break;
    case UIWidget::radiobutton:  widget = std::make_unique<RadioButton>(); break;
    case UIWidget::scrollview:  widget = std::make_unique<ScrollView>(); break;
    case UIWidget::scrollbar:  widget = std::make_unique<ScrollBar>(); break;
    case UIWidget::slider:  widget = std::make_unique<Slider>(); break;
    case UIWidget::progressbar:  widget = std::make_unique<ProgressBar>(); break;
    case UIWidget::spinedit:  widget = std::make_unique<SpinEdit>(); break;
    case UIWidget::separator:  widget = std::make_unique<Separator>(); break;
    case UIWidget::panel:  widget = std::make_unique<Panel>(); break;


    case UIWidget::canvas_layout:  widget = std::make_unique<CanvasLayout>(); break;
    case UIWidget::flow_layout:  widget = std::make_unique<FlowLayout>(); break;
    case UIWidget::grid_layout:  widget = std::make_unique<GridLayout>(); break;
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

    std::stringstream formDataBuffer;

    LayoutParser layout_parser;
    layout_parser.compile(input_src, formDataBuffer);

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



    auto const formData = formDataBuffer.str();
    InputStream formStream(reinterpret_cast<uint8_t const *>(formData.data()), formData.size());

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
