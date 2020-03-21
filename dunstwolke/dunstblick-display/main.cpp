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

#include "api.hpp"
#include "protocol.hpp"

#include "tcphost.hpp"

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
	if(not root_widget)
		return;
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

#include <iostream>

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

static std::ostream & operator<< (std::ostream & stream, CallbackID cb)
{
	stream << "{" << cb.value << "}";
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


static std::ostream & operator<< (std::ostream & stream, UISize val)
{
	stream << val.w << " × " << val.h;
	return stream;
}


static std::ostream & operator<< (std::ostream & stream, UIPoint val)
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

void trigger_callback(CallbackID cid)
{
	if(cid.is_null()) // ignore empty callbacks
		return;

	CommandBuffer buffer { ServerMessageType::eventCallback };
	buffer.write_id(cid.value);

	send_message(buffer);
}

void trigger_propertyChanged(ObjectID oid, PropertyName name, UIValue value)
{
	if(oid.is_null())
		return;
	if(name.is_null())
		return;
	if(value.index() == 0)
		return;

	CommandBuffer buffer { ServerMessageType::propertyChanged };
	buffer.write_id(oid.value);
	buffer.write_id(name.value);
	buffer.write_value(value, true);

	send_message(buffer);
}

static Widget * get_mouse_widget(int x, int y)
{
	if(not root_widget)
		return nullptr;
	else if(Widget::capturingWidget)
		return Widget::capturingWidget;
	else
		return root_widget->hitTest(x, y);
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
	      "DunstBlick Frontend *FLOAT*",
	      SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
	      800, 600,
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

	auto const startup = SDL_GetTicks();

	xstd::resource<SDL_Cursor*, SDL_FreeCursor> cursors[SDL_NUM_SYSTEM_CURSORS];
	for(size_t i = 0; i < SDL_NUM_SYSTEM_CURSORS; i++)
	{
		cursors[i].reset(SDL_CreateSystemCursor(SDL_SystemCursor(i)));
		assert(cursors[i] != nullptr);
	}

	SDL_SystemCursor currentCursor = SDL_SYSTEM_CURSOR_ARROW;
	SDL_SetCursor(cursors[currentCursor].get());

	// right now, serve with TCP:1309
	TcpHost tcpHost { 1309 };

	set_protocol_adapter(ProtocolAdapter::createFrom(tcpHost));

	UIPoint mouse_pos { 0, 0 };

	while(not shutdown_app_requested)
	{
		do_communication();

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
					mouse_pos.x = e.motion.x;
					mouse_pos.y = e.motion.y;
					if(not root_widget)
						break;
					if(auto * child = get_mouse_widget(e.motion.x, e.motion.y); child != nullptr)
					{
						// only move focus if mouse is not captured
						if(Widget::capturingWidget == nullptr)
							ui_set_mouse_focus(child);
						child->processEvent(e);
					}
					break;
				}

				case SDL_MOUSEBUTTONUP:
				case SDL_MOUSEBUTTONDOWN:
				{
					// Only allow left button interaction with all widgets
					if(e.button.button != SDL_BUTTON_LEFT)
						break;

					if(not root_widget)
						break;

					if(auto * child = get_mouse_widget(e.button.x, e.button.y); child != nullptr)
					{
						ui_set_mouse_focus(child);

						if((e.type == SDL_MOUSEBUTTONUP) and child->isKeyboardFocusable())
							ui_set_keyboard_focus(child);

						child->processEvent(e);
					}
					break;
				}

				case SDL_MOUSEWHEEL:
				{
					if(not root_widget)
						break;
					if(auto * child = get_mouse_widget(mouse_pos.x, mouse_pos.y); child != nullptr)
					{
						ui_set_mouse_focus(child);

						child->processEvent(e);
					}
					break;
				}
			}
		}

		SDL_SystemCursor nextCursor;
		if(mouse_focused_widget)
			nextCursor = mouse_focused_widget->getCursor(mouse_pos);
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

            if(root_widget) {
                SDL_Rect clipRect{ 0, 0 };
                SDL_GetRendererOutputSize(context().renderer, &clipRect.w, &clipRect.h);
                context().renderer.setClipRect(clipRect);
				root_widget->paint();
            }

			int mx, my;
			SDL_GetMouseState(&mx, &my);

			if(SDL_GetKeyboardState(nullptr)[SDL_SCANCODE_F3])
			{
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
