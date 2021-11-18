#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dunstblick.h>
#include <unistd.h>

#define ROOT_LAYOUT 1
#define OBJ_ROOT 1
#define PROP_RESULT 1

#define DBCHECKED(_X)                                                                                                  \
    do {                                                                                                               \
        dunstblick_Error err = _X;                                                                                     \
        if (err != DUNSTBLICK_ERROR_NONE) {                                                                            \
            printf("failed to execute " #_X ": %d\n", err);                                                            \
            return;                                                                                                    \
        }                                                                                                              \
    } while (0)

#define DBCHECKED_MAIN(_X)                                                                                             \
    do {                                                                                                               \
        dunstblick_Error err = _X;                                                                                     \
        if (err != DUNSTBLICK_ERROR_NONE) {                                                                            \
            printf("failed to execute " #_X ": %d\n", err);                                                            \
            return 1;                                                                                                  \
        }                                                                                                              \
    } while (0)

/// Simple routine that loads a file
/// and returns both a buffer and the size of the file.
bool load_file(char const * fileName, void ** buffer, size_t * len);

enum MathCommand
{
    COPY = 0,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE
};

struct AppState
{
    float current_value;
    char current_input[64];
    bool shows_result;
    enum MathCommand next_command;
};

static struct AppState * createAppState()
{
    struct AppState * state = malloc(sizeof(struct AppState));
    assert(state != NULL);

    state->current_value = 0.0f;
    memset(state->current_input, 0, sizeof state->current_input);
    state->shows_result = false;
    state->next_command = COPY;

    return state;
}

struct AppState * getAppState(dunstblick_Connection * con)
{
    return dunstblick_GetUserData(con);
}

static void refresh_screen(dunstblick_Connection * con)
{
    struct AppState * app = getAppState(con);

    dunstblick_Value result = {
        .type = DUNSTBLICK_TYPE_STRING,
        .value =
            {
                .string = app->current_input,
            },
    };

    dunstblick_Error error = dunstblick_SetProperty(con, OBJ_ROOT, PROP_RESULT, &result);
    if (error != DUNSTBLICK_ERROR_NONE)
        printf("failed to refresh screen: %d\n", error);
}

static void enter_char(struct AppState * app, char c)
{
    if (app->shows_result)
        strcpy(app->current_input, "");

    char buf[2] = {c, 0};
    strcat(app->current_input, buf);
    app->shows_result = false;
}

static void execute_command(struct AppState * app)
{
    float val = strtof(app->current_input, NULL);
    switch (app->next_command) {
        case COPY:
            app->current_value = val;
            break;
        case ADD:
            app->current_value += val;
            break;
        case SUBTRACT:
            app->current_value -= val;
            break;
        case MULTIPLY:
            app->current_value *= val;
            break;
        case DIVIDE:
            app->current_value /= val;
            break;
    }
    app->shows_result = true;
}

uint8_t const layout_src[] = {
#include "layout.h"
};

unsigned char tvg_icon[] = {
  0x72, 0x56, 0x01, 0x0a, 0x18, 0x00, 0x18, 0x00, 0x01, 0x00, 0x00, 0x00,
  0x00, 0xff, 0x03, 0x0b, 0x00, 0x08, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04,
  0x04, 0x04, 0x04, 0x04, 0x00, 0x1c, 0x00, 0x08, 0x01, 0x00, 0x44, 0x05,
  0x00, 0x00, 0x08, 0x00, 0x08, 0x00, 0x00, 0x00, 0x4c, 0x00, 0x10, 0x02,
  0x00, 0x50, 0x05, 0x00, 0x00, 0x08, 0x00, 0x08, 0x00, 0x00, 0x00, 0x44,
  0x00, 0x58, 0x01, 0x00, 0x1c, 0x05, 0x00, 0x00, 0x08, 0x00, 0x08, 0x00,
  0x00, 0x00, 0x14, 0x00, 0x50, 0x02, 0x00, 0x10, 0x05, 0x00, 0x00, 0x08,
  0x00, 0x08, 0x00, 0x00, 0x00, 0x1c, 0x00, 0x08, 0x00, 0x1c, 0x00, 0x10,
  0x02, 0x00, 0x20, 0x01, 0x00, 0x44, 0x02, 0x00, 0x10, 0x01, 0x00, 0x1c,
  0x00, 0x1c, 0x00, 0x28, 0x02, 0x00, 0x30, 0x01, 0x00, 0x24, 0x02, 0x00,
  0x28, 0x01, 0x00, 0x1c, 0x00, 0x2c, 0x00, 0x28, 0x02, 0x00, 0x30, 0x01,
  0x00, 0x34, 0x02, 0x00, 0x28, 0x01, 0x00, 0x2c, 0x00, 0x3c, 0x00, 0x28,
  0x02, 0x00, 0x30, 0x01, 0x00, 0x44, 0x02, 0x00, 0x28, 0x01, 0x00, 0x3c,
  0x00, 0x1c, 0x00, 0x38, 0x02, 0x00, 0x40, 0x01, 0x00, 0x24, 0x02, 0x00,
  0x38, 0x01, 0x00, 0x1c, 0x00, 0x2c, 0x00, 0x38, 0x02, 0x00, 0x40, 0x01,
  0x00, 0x34, 0x02, 0x00, 0x38, 0x01, 0x00, 0x2c, 0x00, 0x3c, 0x00, 0x38,
  0x02, 0x00, 0x40, 0x01, 0x00, 0x44, 0x02, 0x00, 0x38, 0x01, 0x00, 0x3c,
  0x00, 0x1c, 0x00, 0x48, 0x02, 0x00, 0x50, 0x01, 0x00, 0x24, 0x02, 0x00,
  0x48, 0x01, 0x00, 0x1c, 0x00, 0x2c, 0x00, 0x48, 0x02, 0x00, 0x50, 0x01,
  0x00, 0x34, 0x02, 0x00, 0x48, 0x01, 0x00, 0x2c, 0x00, 0x3c, 0x00, 0x48,
  0x02, 0x00, 0x50, 0x01, 0x00, 0x44, 0x02, 0x00, 0x48, 0x01, 0x00, 0x3c,
  0x00
};
unsigned int tvg_icon_len = 253;

int main()
{
    dunstblick_Provider * provider = dunstblick_OpenProvider(
        "Calculator",
        "A classic non-scientific calculator",
        tvg_icon, tvg_icon_len
    );
    if (!provider)
        return 1;

    // Upload the compiled layout to the server,
    // so we can use dunstblick_SetView to display
    // the UI layout.
    DBCHECKED_MAIN(dunstblick_AddResource(provider, ROOT_LAYOUT, DUNSTBLICK_RESOURCE_LAYOUT, layout_src, sizeof(layout_src)));

    bool app_running = true;
    while (app_running) {
        dunstblick_Event event;
        if(dunstblick_WaitEvent(provider, &event) != DUNSTBLICK_ERROR_GOT_EVENT)
            abort();
        switch(event.type)
        {
            case DUNSTBLICK_EVENT_CONNECTED:
            {
                dunstblick_Connection * const connection = event.connected.connection;

                struct AppState * app = createAppState();

                dunstblick_SetUserData(connection, app);

                // Create our root object
                // that allows us to display changing values.
                // As dunstblick does not allow you to mutate widgets directly,
                // you require to create objects and bind widget properties to
                // object properties in order to mutate state.
                {
                    dunstblick_Object * root_obj = dunstblick_BeginChangeObject(connection, OBJ_ROOT);
                    if (root_obj == NULL) {
                        printf("failed to create object!\n");
                        dunstblick_CloseConnection(connection, "Could not change object!");
                        return 1;
                    }

                    // Create a string property named PROP_RESULT
                    // with an empty string as initial value.
                    dunstblick_Value result = {
                        .type = DUNSTBLICK_TYPE_STRING,
                        .value =
                            {
                                .string = "",
                            },
                    };
                    DBCHECKED_MAIN(dunstblick_SetObjectProperty(root_obj, PROP_RESULT, &result));

                    // CommitObject commits the object change to the ui server.
                    DBCHECKED_MAIN(dunstblick_CommitObject(root_obj));
                }

                // After base is set up,
                // both set the current view (UI layout) and root object.
                // the root object is used for all bindings in the layouts
                // except for widgets with a changed 'binding-context'.
                DBCHECKED_MAIN(dunstblick_SetView(connection, ROOT_LAYOUT));
                DBCHECKED_MAIN(dunstblick_SetRoot(connection, OBJ_ROOT));
                
                break;
            }
            case DUNSTBLICK_EVENT_DISCONNECTED:
            {
                // Clean up our data
                free(dunstblick_GetUserData(event.disconnected.connection));
                break;
            }
            case DUNSTBLICK_EVENT_WIDGET:
            {
                dunstblick_Connection * const con = event.widget_event.connection;

                struct AppState * app = getAppState(con);

                switch (event.widget_event.event) {
                    case 1:
                    case 2:
                    case 3:
                    case 4:
                    case 5:
                    case 6:
                    case 7:
                    case 8:
                    case 9:
                    case 10: {
                        int number = event.widget_event.event % 10;
                        enter_char(app, (char)('0' + number));
                        break;
                    }

                    case 11: // "+"
                        execute_command(app);
                        app->next_command = ADD;
                        break;

                    case 12: // "-"
                        execute_command(app);
                        app->next_command = SUBTRACT;
                        break;

                    case 13: // "*"
                        execute_command(app);
                        app->next_command = MULTIPLY;
                        break;

                    case 14: // "/"
                        execute_command(app);
                        app->next_command = DIVIDE;
                        break;

                    case 15: // "C"
                        strcpy(app->current_input, "0");
                        app->current_value = 0.0f;
                        app->shows_result = false;
                        app->next_command = COPY;
                        break;

                    case 16: // "CE"
                        strcpy(app->current_input, "");
                        app->shows_result = false;
                        break;

                    case 17: // ','
                    {
                        if (strchr(app->current_input, '.') == NULL)
                            enter_char(app, '.');
                        break;
                    }

                    case 18: // "="
                    {
                        execute_command(app);
                        app->next_command = COPY;
                        break;
                    }

                    default:
                        printf("got handled callback: %d\n", event.widget_event.event);
                        fflush(stdout);
                        break;
                }

                if (app->shows_result)
                    sprintf(app->current_input, "%f", (double)app->current_value);

                refresh_screen(con);
                break;
            }
            case DUNSTBLICK_EVENT_PROPERTY_CHANGED:
            {
                printf("Property changed!\n");

                break;
            }
        }
    }

    dunstblick_CloseProvider(provider);
    return 0;
}
