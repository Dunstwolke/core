#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dunstblick.h>

static bool app_running = true;

/*
 * Button {
 *   on-click: callback("click=42");
 *   Label {
 *     text: "Click me!";
 *   }
 * }
 */
static uint8_t const compiled_layout[] = {
    0x01, 0x1e, 0x2a, 0x00, 0x02, 0x0a, 0x09, 0x43, 0x6c, 0x69, 0x63, 0x6b, 0x20, 0x6d, 0x65, 0x21, 0x00, 0x00, 0x00};

static void on_event(dunstblick_Connection * connection,
                     dunstblick_EventID event,
                     dunstblick_WidgetName widget,
                     void * userData)
{
    assert(event == 42);
    app_running = false;
}

static void on_connection(dunstblick_Provider * provider,
                          dunstblick_Connection * connection,
                          char const * clientName,
                          char const * password,
                          dunstblick_Size screenSize,
                          dunstblick_ClientCapabilities capabilities,
                          void * userData)
{
    dunstblick_SetEventCallback(connection, on_event, NULL);
    dunstblick_SetView(connection, 1);
}

int main()
{
    dunstblick_Provider * provider = dunstblick_OpenProvider(
        "Minimal Example",
        "This example is a minimal example of a Dunstblick application",
        NULL, 0);
    if (!provider)
        return 1;

    dunstblick_SetConnectedCallback(provider, on_connection, NULL);

    dunstblick_AddResource(provider, 1, DUNSTBLICK_RESOURCE_LAYOUT, compiled_layout, sizeof compiled_layout);

    while (app_running) {
        dunstblick_PumpEvents(provider);
    }

    dunstblick_CloseProvider(provider);
    return 0;
}
