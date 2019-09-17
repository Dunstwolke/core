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

static UIValue deserialize_value(UIType type, InputStream & stream)
{
	switch(type)
	{
		case UIType::invalid:
			throw std::runtime_error("Invalid property serialization: 'invalid' object discovered.");

		case UIType::objectlist:
		{
			ObjectList list;
			while(true)
			{
				ObjectID id(stream.read_uint());
				if(id.is_null())
					break;
				list.push_back(ObjectRef { id });
			}
			return list;
		}

		case UIType::enumeration:
			return stream.read_byte();

		case UIType::integer:
			return gsl::narrow<int>(stream.read_uint());

		case UIType::resource:
			return UIResourceID(stream.read_uint());

		case UIType::object: // objects are always references!
			return ObjectRef { ObjectID(stream.read_uint()) };

		case UIType::number:
			return gsl::narrow<float>(stream.read_float());

		case UIType::boolean:
			return (stream.read_byte() != 0);

		case UIType::color:
		{
			UIColor color;
			color.r = stream.read_byte();
			color.g = stream.read_byte();
			color.b = stream.read_byte();
			color.a = stream.read_byte();
			return color;
		}

		case UIType::size:
		{
			SDL_Size size;
			size.w = gsl::narrow<int>(stream.read_uint());
			size.h = gsl::narrow<int>(stream.read_uint());
			return size;
		}

		case UIType::point:
		{
			SDL_Point pos;
			pos.x = gsl::narrow<int>(stream.read_uint());
			pos.y = gsl::narrow<int>(stream.read_uint());
			return pos;
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

		case UIType::sizelist:
		{
			UISizeList list;

			auto len = stream.read_uint();

			list.resize(len);
			for(size_t i = 0; i < list.size(); i += 4)
			{
				uint8_t value = stream.read_byte();
				for(size_t j = 0; j < std::min(4UL, list.size() - i); j++)
				{
					switch((value >> (2 * j)) & 0x3)
					{
						case 0: list[i + j] = UISizeAutoTag { }; break;
						case 1: list[i + j] = UISizeExpandTag { }; break;
						case 2: list[i + j] = 0; break;
						case 3: list[i + j] = 1.0f; break;
					}
				}
			}

			for(size_t i = 0; i < list.size(); i++)
			{
				switch(list[i].index())
				{
					case 2: // pixels
						list[i] = int(stream.read_uint());
						break;
					case 3: // percentage
						list[i] = stream.read_float();
						break;
				}
			}

			return std::move(list);
		}

	}
	assert(false and "property type not in table yet!");
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
				auto const value = deserialize_value(getPropertyType(property), stream);
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

static void set_ui_root(UIResourceID id)
{
	root_widget = load_widget(id);

	// focused widgets are destroyed, so remove the reference here!
	keyboard_focused_widget = nullptr;
	mouse_focused_widget = nullptr;

	update_layout();
}

static void set_object_root(ObjectID id)
{
	auto ref = ObjectRef { id };
	if(ref) {
		root_object = ref;
		update_layout();
	}
}

static Object deserialize_object(InputStream & stream)
{
	ObjectID id = ObjectID(stream.read_uint());
	Object obj { id };
	while(true)
	{
		auto const type = stream.read_enum<UIType>();
		if(type == UIType::invalid)
			break;
		auto const name = PropertyName(stream.read_uint());

		UIValue const value = deserialize_value(type, stream);

		obj.add(name, std::move(value));
	}
	return obj;
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

	set_resource(UIResourceID(1), load_and_compile(layout_parser, "./layouts/development.uit"));
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

	InputStream istream1(serdata_object1);
	InputStream istream2(serdata_object2);
	add_or_update_object(deserialize_object(istream1));
	add_or_update_object(deserialize_object(istream2));

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

						if((e.type == SDL_MOUSEBUTTONUP) and (e.button.button == SDL_BUTTON_LEFT))
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
