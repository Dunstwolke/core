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
        .string = app->current_input,
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

static void cb_onUiEvent(dunstblick_Connection * con, dunstblick_EventID cid, dunstblick_WidgetName obj, void * context)
{
    struct AppState * app = getAppState(con);

    switch (cid) {
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
            int number = cid % 10;
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
            printf("got handled callback: %d\n", cid);
            fflush(stdout);
            break;
    }

    if (app->shows_result)
        sprintf(app->current_input, "%f", (double)app->current_value);

    refresh_screen(con);
}

static void cb_onConnected(dunstblick_Provider * provider,
                           dunstblick_Connection * connection,
                           char const * clientName,
                           char const * password,
                           dunstblick_Size screenSize,
                           dunstblick_ClientCapabilities capabilities,
                           void * userData)
{
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
            return;
        }

        // Create a string property named PROP_RESULT
        // with an empty string as initial value.
        dunstblick_Value result = {
            .type = DUNSTBLICK_TYPE_STRING,
            .string = "",
        };
        DBCHECKED(dunstblick_SetObjectProperty(root_obj, PROP_RESULT, &result));

        // CommitObject commits the object change to the ui server.
        DBCHECKED(dunstblick_CommitObject(root_obj));
    }

    dunstblick_SetEventCallback(connection, cb_onUiEvent, NULL);

    // After base is set up,
    // both set the current view (UI layout) and root object.
    // the root object is used for all bindings in the layouts
    // except for widgets with a changed 'binding-context'.
    DBCHECKED(dunstblick_SetView(connection, ROOT_LAYOUT));
    DBCHECKED(dunstblick_SetRoot(connection, OBJ_ROOT));
}

static void cb_onDisconnected(dunstblick_Provider * provider,
                              dunstblick_Connection * connection,
                              dunstblick_DisconnectReason reason,
                              void * userData)
{
    // Clean up our data
    free(dunstblick_GetUserData(connection));
}

uint8_t const layout_src[] = {
#include "layout.h"
};

int main()
{
    dunstblick_Provider * provider = dunstblick_OpenProvider("Calculator");
    if (!provider)
        return 1;

    DBCHECKED_MAIN(dunstblick_SetConnectedCallback(provider, cb_onConnected, NULL));
    DBCHECKED_MAIN(dunstblick_SetDisconnectedCallback(provider, cb_onDisconnected, NULL));

    // Upload the compiled layout to the server,
    // so we can use dunstblick_SetView to display
    // the UI layout.
    DBCHECKED_MAIN(
        dunstblick_AddResource(provider, ROOT_LAYOUT, DUNSTBLICK_RESOURCE_LAYOUT, layout_src, sizeof(layout_src)));

    bool app_running = true;
    while (app_running) {
        DBCHECKED_MAIN(dunstblick_WaitEvents(provider));
    }

    dunstblick_CloseProvider(provider);
    return 0;
}
