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
static uint8_t const compiled_layout[] = { 0x01, 0x1e, 0x2a, 0x00, 0x02, 0x0a, 0x09, 0x43, 0x6c, 0x69, 0x63, 0x6b, 0x20, 0x6d, 0x65, 0x21, 0x00, 0x00, 0x00};

int main()
{
    dunstblick_Provider * provider = dunstblick_OpenProvider(
        "Minimal Example",
        "This example is a minimal example of a Dunstblick application",
        NULL, 0);
    if (!provider)
        return 1;

    dunstblick_AddResource(provider, 1, DUNSTBLICK_RESOURCE_LAYOUT, compiled_layout, sizeof compiled_layout);

    bool app_running = true;
    while (app_running) {
        dunstblick_Event event;
        if(dunstblick_WaitEvent(provider, &event) != DUNSTBLICK_ERROR_GOT_EVENT)
            abort();
        switch(event.type)
        {
            case DUNSTBLICK_EVENT_CONNECTED:
                dunstblick_SetView(event.connected.connection, 1);
                printf("Device connected!\n");
                break;
                
            case DUNSTBLICK_EVENT_WIDGET:
                assert(event.widget_event.event == 42);
                app_running = false;
                break;
        }
    }

    dunstblick_CloseProvider(provider);
    return 0;
}
