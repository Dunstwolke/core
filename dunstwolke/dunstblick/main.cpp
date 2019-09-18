#include <SDL.h>
#include <SDL_image.h>
#include <sdl2++/renderer>
#include <vector>
#include <filesystem>

#include "types.hpp"
#include "widget.hpp"
#include "layouts.hpp"
#include "widgets.hpp"
#include "resources.hpp"

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

static std::unique_ptr<Widget> root_widget;
static std::unique_ptr<RenderContext> current_rc;

static Widget * keyboard_focused_widget = nullptr;
static Widget * mouse_focused_widget = nullptr;

static SDL_Rect screen_rect = { 0, 0, 0, 0 };

static ObjectRef root_object = ObjectRef(nullptr);

static void ui_set_keyboard_focus(Widget * widget)
{
	if(keyboard_focused_widget == widget)
		return;

	if(keyboard_focused_widget != nullptr) {
		SDL_Event e;
		e.type = UI_EVENT_LOST_KEYBOARD_FOCUS;
		e.common.timestamp = SDL_GetTicks();
		keyboard_focused_widget->processEvent(e);
	}
	keyboard_focused_widget = widget;
	if(keyboard_focused_widget != nullptr) {
		SDL_Event e;
		e.type = UI_EVENT_GOT_KEYBOARD_FOCUS;
		e.common.timestamp = SDL_GetTicks();
		keyboard_focused_widget->processEvent(e);
	}
}

static void ui_set_mouse_focus(Widget * widget)
{
	if(mouse_focused_widget == widget)
		return;

	if(mouse_focused_widget != nullptr) {
		SDL_Event e;
		e.type = UI_EVENT_LOST_MOUSE_FOCUS;
		e.common.timestamp = SDL_GetTicks();
		mouse_focused_widget->processEvent(e);
	}
	mouse_focused_widget = widget;
	if(mouse_focused_widget != nullptr) {
		SDL_Event e;
		e.type = UI_EVENT_GOT_MOUSE_FOCUS;
		e.common.timestamp = SDL_GetTicks();
		mouse_focused_widget->processEvent(e);
	}
}

RenderContext & context() {
	return *current_rc;
}

static std::unique_ptr<Widget> deserialize_widget(UIWidget widgetType, InputStream & stream)
{
	auto widget = Widget::create(widgetType);
	assert(widget);

	UIProperty property;
	do
	{
		bool isBinding;
		std::tie(property, isBinding) = stream.read_property_enum();
		if(property != UIProperty::invalid)
		{
			if(isBinding) {
				auto const name = PropertyName(stream.read_uint());
				widget->setPropertyBinding(property, name);
			} else {
				auto const value = stream.read_value(getPropertyType(property));
				widget->setProperty(property, value);
			}
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

static std::unique_ptr<Widget> deserialize_widget(InputStream & stream)
{
	auto const widgetType = stream.read_enum<UIWidget>();
	return deserialize_widget(widgetType, stream);
}



static void update_layout()
{
	root_widget->updateBindings(root_object);
	root_widget->updateWantedSize();
	root_widget->layout(screen_rect);
}

std::unique_ptr<Widget> load_widget(UIResourceID id)
{
	if(auto resource = find_resource(id); resource)
	{
		if(resource->index() != int(ResourceKind::layout))
			throw std::runtime_error("invalid resource: wrong kind!");

		auto const & layout = std::get<LayoutResource>(*resource);

		InputStream stream = layout.get_stream();

		auto widget = deserialize_widget(stream);
		widget->templateID = id;
		return widget;
	}
	else
	{
		throw std::runtime_error("could not find the right resource!");
	}
}

void set_ui_root(UIResourceID id)
{
	root_widget = load_widget(id);

	// focused widgets are destroyed, so remove the reference here!
	keyboard_focused_widget = nullptr;
	mouse_focused_widget = nullptr;

	update_layout();
}

void set_object_root(ObjectID id)
{
	auto ref = ObjectRef { id };
	if(ref) {
		root_object = ref;
		update_layout();
	}
}

#include <fstream>
#include <iostream>

static LayoutResource load_and_compile(LayoutParser const & parser, std::string const & fileName)
{
	std::ifstream input_src(fileName);

	std::stringstream formDataBuffer;
	parser.compile(input_src, formDataBuffer);

	auto formData = formDataBuffer.str();
	return LayoutResource(reinterpret_cast<uint8_t const *>(formData.data()), formData.size());
}

uint8_t const serdata_object1[] =
	"\x01" // object-id : varint
	// property name : varint, type : u8, value : TypeFor(type)
	"\x0C\x17\x02" // ObjectRef, 23, 2
	"\x01\x2A\x19" // Integer, 42, 25
	"\x00" // end of properties
;

uint8_t const serdata_object2[] =
	"\x02" // object-id 2
	"\x01\x2A\x32" // integer, 42, 50
	"\x00" // end of properties
;

static std::ostream & operator<< (std::ostream & stream, std::monostate)
{
	stream << "<NULL>";
	return stream;
}

static std::ostream & operator<< (std::ostream & stream, ObjectRef ref)
{
	stream << "→[" << ref.id.value << "]";
	return stream;
}


static std::ostream & operator<< (std::ostream & stream, ObjectList const & list)
{
	stream << "[";
	for(auto const & val : list) {
		stream << " " << val;
	}
	stream << " ]";
	return stream;
}

static std::ostream & operator<< (std::ostream & stream, UIMargin)
{
	stream << "<margin>";
	return stream;
}


static std::ostream & operator<< (std::ostream & stream, UIColor col)
{
	stream << std::setw(2) << std::hex << "r=" << col.r << ", g=" << col.g << ", b=" << col.b << ", a=" << col.a;
	return stream;
}


static std::ostream & operator<< (std::ostream & stream, SDL_Size val)
{
	stream << val.w << " × " << val.h;
	return stream;
}


static std::ostream & operator<< (std::ostream & stream, SDL_Point val)
{
	stream << val.x << ", " << val.y;
	return stream;
}


static std::ostream & operator<< (std::ostream & stream, UIResourceID)
{
	stream << "<ui resource id>";
	return stream;
}

static std::ostream & operator<< (std::ostream & stream, UISizeList)
{
	stream << "<ui size list>";
	return stream;
}

static void dump_object(Object const & obj)
{
	std::cout << "Object[" << obj.get_id().value << "]" << std::endl;
	for(auto const & prop : obj.properties)
	{
		std::cout << "\t[" << prop.first.value << "] : " << to_string(prop.second.type) << " = ";
		std::visit([](auto const & val) {
			std::cout << val;
		}, prop.second.value);
		std::cout << std::endl;
	}
}

int main()
{
	//////////////////////////////////////////////////////////////////////////////
	if(SDL_Init(SDL_INIT_EVERYTHING) < 0) {
		exit_sdl_error();
	}
	atexit(SDL_Quit);

	if(TTF_Init() < 0) {
		exit_sdl_error();
	}
	atexit(TTF_Quit);

	if(IMG_Init(IMG_INIT_PNG) < 0) {
		exit_sdl_error();
	}
	atexit(IMG_Quit);

	//////////////////////////////////////////////////////////////////////////////

	SDL_Window * window = SDL_CreateWindow(
	      "DunstBlick Frontend",
	      SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
	      1280, 720,
	      SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
	      );
	if(window == nullptr) {
		exit_sdl_error();
	}

	SDL_GetWindowSize(window, &screen_rect.w, &screen_rect.h);

	current_rc = std::make_unique<RenderContext>(
		sdl2::renderer { window },
		"./fonts/Roboto-Regular.ttf",
		"./fonts/CrimsonPro-Regular.ttf",
		"./fonts/SourceCodePro-Regular.ttf"
	);

	context().renderer.setBlendMode(SDL_BLENDMODE_BLEND); // enable alpha blend

	//////////////////////////////////////////////////////////////////////////////
	// prepare system for development here

	printf("cwd = %s\n", std::filesystem::current_path().c_str());
	fflush(stdout);

	LayoutParser layout_parser;
	layout_parser.knownProperties.emplace("child", PropertyName(23));
	layout_parser.knownProperties.emplace("sinewave", PropertyName(42));
	layout_parser.knownProperties.emplace("profile-picture", PropertyName(1));
	layout_parser.knownProperties.emplace("name", PropertyName(2));
	layout_parser.knownProperties.emplace("contacts", PropertyName(3));

	layout_parser.knownResources.emplace("root_layout", UIResourceID(1));
	layout_parser.knownResources.emplace("house.png", UIResourceID(2));
	layout_parser.knownResources.emplace("person-male-01.png", UIResourceID(3));
	layout_parser.knownResources.emplace("person-female-01.png", UIResourceID(4));
	layout_parser.knownResources.emplace("contact-item", UIResourceID(5));

	set_resource(UIResourceID(1), load_and_compile(layout_parser, "./layouts/calculator/root.ui"));
	set_resource(UIResourceID(5), load_and_compile(layout_parser, "./layouts/contact.uit"));

	{
		auto * tex = IMG_LoadTexture(context().renderer, "./images/small-test.png");
		set_resource(UIResourceID(2), BitmapResource(sdl2::texture(std::move(tex))));
	}

	{
		auto * tex = IMG_LoadTexture(context().renderer, "./images/person-male-01.png");
		set_resource(UIResourceID(3), BitmapResource(sdl2::texture(std::move(tex))));
	}

	{
		auto * tex = IMG_LoadTexture(context().renderer, "./images/person-female-01.png");
		set_resource(UIResourceID(4), BitmapResource(sdl2::texture(std::move(tex))));
	}

	add_or_update_object(InputStream(serdata_object1).read_object());
	add_or_update_object(InputStream(serdata_object2).read_object());

	//////////////////////////////////////////////////////////////////////////////
	// emulate some API calls here

	set_ui_root(UIResourceID(1));
	set_object_root(ObjectID(1));

	//////////////////////////////////////////////////////////////////////////////
	{
		auto & list_prop = root_object->add(PropertyName(3), ObjectList { });

		auto & list = std::get<ObjectList>(list_prop.value);

		for(size_t i = 0; i < 10; i++)
		{
			Object obj { ObjectID(100 + i) };

			obj.add(PropertyName(1), (rand() % 2) ? UIResourceID(4) : UIResourceID(3));
			obj.add(PropertyName(2), "Object " + std::to_string(i));

			list.emplace_back(ObjectRef { add_or_update_object(std::move(obj)) });
		}

		for(auto const & obj : get_object_registry())
			dump_object(obj.second);
	}
	//////////////////////////////////////////////////////////////////////////////

	auto const startup = SDL_GetTicks();

	xstd::resource<SDL_Cursor*, SDL_FreeCursor> cursors[SDL_NUM_SYSTEM_CURSORS];
	for(size_t i = 0; i < SDL_NUM_SYSTEM_CURSORS; i++)
	{
		cursors[i].reset(SDL_CreateSystemCursor(SDL_SystemCursor(i)));
		assert(cursors[i] != nullptr);
	}

	SDL_SystemCursor currentCursor = SDL_SYSTEM_CURSOR_ARROW;
	SDL_SetCursor(cursors[currentCursor].get());

	while(not shutdown_app_requested)
	{
		SDL_Event e;
		while(SDL_PollEvent(&e))
		{
			switch(e.type) {
				case SDL_QUIT:
					shutdown_app_requested = true;
					break;
				case SDL_WINDOWEVENT:
					switch(e.window.event)
					{
						case SDL_WINDOWEVENT_RESIZED:
							screen_rect.w = e.window.data1;
							screen_rect.h = e.window.data2;
							update_layout();
							break;
					}
					break;

				// keyboard events:
				case SDL_KEYDOWN:
				case SDL_KEYUP:
				case SDL_TEXTEDITING:
				case SDL_TEXTINPUT:
				case SDL_KEYMAPCHANGED:
				{
					if(keyboard_focused_widget != nullptr)
					{
						keyboard_focused_widget->processEvent(e);
					}
					break;
				}

				// mouse events:
				case SDL_MOUSEMOTION:
				{
					if(auto * child = root_widget->hitTest(e.motion.x, e.motion.y); child != nullptr)
					{
						ui_set_mouse_focus(child);

						// adjust event
						e.motion.x -= child->actual_bounds.x;
						e.motion.y -= child->actual_bounds.y;

						child->processEvent(e);
					}
					break;
				}

				case SDL_MOUSEBUTTONUP:
				case SDL_MOUSEBUTTONDOWN:
				{
					if(auto * child = root_widget->hitTest(e.button.x, e.button.y); child != nullptr)
					{
						ui_set_mouse_focus(child);

						if((e.type == SDL_MOUSEBUTTONUP) and (e.button.button == SDL_BUTTON_LEFT) and child->isKeyboardFocusable())
							ui_set_keyboard_focus(child);

						// adjust event
						e.button.x -= child->actual_bounds.x;
						e.button.y -= child->actual_bounds.y;

						child->processEvent(e);
					}
					break;
				}

				case SDL_MOUSEWHEEL:
				{
					if(auto * child = root_widget->hitTest(e.wheel.x, e.wheel.y); child != nullptr)
					{
						ui_set_mouse_focus(child);

						// adjust event
						e.wheel.x -= child->actual_bounds.x;
						e.wheel.y -= child->actual_bounds.y;

						child->processEvent(e);
					}
					break;
				}
			}
		}

		SDL_SystemCursor nextCursor;
		if(mouse_focused_widget)
			nextCursor = mouse_focused_widget->getCursor();
		else
			nextCursor = SDL_SYSTEM_CURSOR_ARROW;

		if(nextCursor != currentCursor)
		{
			currentCursor = nextCursor;
			SDL_SetCursor(cursors[currentCursor].get());
		}


		auto const time = SDL_GetTicks() - startup;

		auto const windowFlags = SDL_GetWindowFlags(window);

		// draw UI when window is visible
		if((windowFlags & (SDL_WINDOW_MINIMIZED | SDL_WINDOW_HIDDEN)) == 0)
		{
			context().renderer.resetClipRect();
			assert(not context().renderer.isClipEnabled());

			context().renderer.setColor(0x00, 0x00, 0x00, 0xFF);
			context().renderer.fillRect(context().renderer.getViewport());

			update_layout();

			if(root_widget)
				root_widget->paint();

			int mx, my;
			SDL_GetMouseState(&mx, &my);

			if(mouse_focused_widget != nullptr)
			{
				context().renderer.setColor(0xFF, 0x00, 0x00);
				context().renderer.drawRect(mouse_focused_widget->actual_bounds);
			}

			if(keyboard_focused_widget != nullptr)
			{
				context().renderer.setColor(0x00, 0xFF, 0x00);
				context().renderer.drawRect(keyboard_focused_widget->actual_bounds);
			}

			context().renderer.present();

			if((windowFlags & (SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_MOUSE_FOCUS)) != 0)
			{
				// 60 FPS with focused window
				SDL_Delay(16);
			}
			else
			{
				// 30 FPS with window in backgound
				SDL_Delay(33);
			}
		}
		else
		{
			// slow update loop when window is not visible
			SDL_Delay(100);
		}

	}

	root_widget.reset();
	current_rc.reset();

	SDL_DestroyWindow(window);

	return 0;
}
