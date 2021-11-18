#ifndef DUNSTBLICK2_H
#define DUNSTBLICK2_H

/// @file
/// @brief This module contains the API of the @ref dunstblick user interface.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef ONLY_FOR_DOXYGEN
#define DOXYGEN_BODY \
  {}
#else
#define DOXYGEN_BODY
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// @brief Enumeration of all available resource types.
enum dunstblick_ResourceKind {
  /// A layout resource contains the compiled description of a widget layout.
  /// Create a compiled layout with the @ref dunstblick-compiler.
  DUNSTBLICK_RESOURCE_LAYOUT = 0,
  /// A raster image resource that contains a common image file like PNG or JPEG.
  DUNSTBLICK_RESOURCE_BITMAP = 1,
  /// A vector image resource that contains a yet unspecified format.
  DUNSTBLICK_RESOURCE_DRAWING = 2,
};

/// @brief Contains a type tag for each possible type a @ref dunstblick_Value can have.
enum dunstblick_Type {
  DUNSTBLICK_TYPE_INTEGER = 1,
  DUNSTBLICK_TYPE_NUMBER = 2,
  DUNSTBLICK_TYPE_STRING = 3,
  DUNSTBLICK_TYPE_ENUMERATION = 4,
  DUNSTBLICK_TYPE_MARGINS = 5,
  DUNSTBLICK_TYPE_COLOR = 6,
  DUNSTBLICK_TYPE_SIZE = 7,
  DUNSTBLICK_TYPE_POINT = 8,
  DUNSTBLICK_TYPE_RESOURCE = 9,
  DUNSTBLICK_TYPE_BOOLEAN = 10,
  DUNSTBLICK_TYPE_OBJECT = 12,
  DUNSTBLICK_TYPE_OBJECTLIST = 13,
  DUNSTBLICK_TYPE_EVENT = 14,
  DUNSTBLICK_TYPE_WIDGET_NAME = 15,
  DUNSTBLICK_TYPE_PROPERTY_NAME = 16,
};

/// @brief Feature flags the display client capabilities.
/// These flags can be used to decide what UI layouts to deliver to the client.
enum dunstblick_ClientCapabilities {
  DUNSTBLICK_CAPS_NONE = 0,     ///< The client has no special capabilities.
  DUNSTBLICK_CAPS_MOUSE = 1,    ///< The client has a mouse available.
  DUNSTBLICK_CAPS_KEYBOARD = 2, ///< The client has a keyboard available.
  DUNSTBLICK_CAPS_TOUCH = 4,    ///< The client has a touchscreen available.
  DUNSTBLICK_CAPS_HIGHDPI = 8,  ///< The client has a high-dpi screen
  DUNSTBLICK_CAPS_TILTABLE =
      16,                                 ///< The client can be tilted and switch between portrait and landscape view (like a mobile device)
  DUNSTBLICK_CAPS_RESIZABLE = 32,         ///< The client area can be resized (for example when it's hosted in a window
                                          ///< instead of a fullscreen application)
  DUNSTBLICK_CAPS_REQ_ACCESSIBILITY = 64, ///< The client wants to have a special UI for improved accessiblity
};

/// @brief Error codes that are returned by a function.
enum dunstblick_Error {
  DUNSTBLICK_ERROR_GOT_EVENT = 1,              ///< The operation was successful and yielded a event.
  DUNSTBLICK_ERROR_NONE = 0,                   ///< The operation was successful.
  DUNSTBLICK_ERROR_INVALID_ARG = -1,           ///< An invalid argument was passed to the function.
  DUNSTBLICK_ERROR_NETWORK = -2,               ///< A network error happened.
  DUNSTBLICK_ERROR_INVALID_TYPE = -3,          ///< An invalid type was passed to a function.
  DUNSTBLICK_ERROR_ARGUMENT_OUT_OF_RANGE = -4, ///< An argument was not in the allowed range.
  DUNSTBLICK_ERROR_OUT_OF_MEMORY = -5,         ///< An allocation failed.
  DUNSTBLICK_ERROR_RESOURCE_NOT_FOUND = -6,    ///< A requested resource was not found.
};

/// @brief Enumeration of possible reasons for a client disconnection.
enum dunstblick_DisconnectReason {
  DUNSTBLICK_DISCONNECT_QUIT = 0,
  DUNSTBLICK_DISCONNECT_SHUTDOWN = 1,
  DUNSTBLICK_DISCONNECT_TIMEOUT = 2,
  DUNSTBLICK_DISCONNECT_NETWORK_ERROR = 3,
  DUNSTBLICK_DISCONNECT_INVALID_DATA = 4,
  DUNSTBLICK_DISCONNECT_PROTOCOL_MISMATCH = 5,
};

/// @brief A unique resource identifier.
typedef uint32_t dunstblick_ResourceID;

/// @brief A unique object handle.
typedef uint32_t dunstblick_ObjectID;

/// @brief Name of an object property.
typedef uint32_t dunstblick_PropertyName;

/// @brief An event id that is defined in the layout.
typedef uint32_t dunstblick_EventID;

/// @brief The name of a widget.
/// This value is either `0` (*unnamed*) or has a user-assigned name that can be
/// used to distinct widgets that use the same event handler.
typedef uint32_t dunstblick_WidgetName;

/// @brief sRGB color value with linear alpha.
/// The RGB colors use the [sRGB](https://en.wikipedia.org/wiki/SRGB) color space,
/// alpha is linearly encoded and blended.
struct dunstblick_Color {
  uint8_t red; ///< Red color channel
  uint8_t green; ///< Green color channel
  uint8_t blue; ///< Blue color channel
  uint8_t alpha; ///< Transparency channel. 128 is 50% alpha
};

/// @brief 2D point in screen space coordinates.
struct dunstblick_Point {
  int32_t x; ///< distance to the left screen border
  int32_t y; ///< distance to the upper screen border
};

/// @brief 2D dimensions.
struct dunstblick_Size {
  uint32_t width; ///< Horizontal extends.
  uint32_t height; ///< Vertical extends.
};

/// @brief Width of margins of a rectangle.
struct dunstblick_Margins {
  uint32_t left, top, right, bottom;
};

/// @brief A type-tagged value for the dunstblick API.
struct dunstblick_Value {
  enum dunstblick_Type type; ///< Type of the value. The union field corresponding to this field is active.
  union {
    int32_t integer;
    uint8_t enumeration;
    float number;
    char const *string;
    dunstblick_ResourceID resource;
    dunstblick_ObjectID object;
    struct dunstblick_Color color;
    struct dunstblick_Size size;
    struct dunstblick_Point point;
    struct dunstblick_Margins margins;
    bool boolean;
    dunstblick_EventID event;
    dunstblick_WidgetName widget_name;
  } value;
};

/// @brief An UI provider that is discoverable by display clients.
/// Created with @ref dunstblick_OpenProvider and destroyed by @ref dunstblick_CloseProvider.
struct dunstblick_Provider DOXYGEN_BODY;

/// @brief A connection of a display client.
/// Functions that operate on connection communicate with the display.
/// Is either destroyed when the connection is closed by the remote host or
/// when @ref dunstblick_CloseConnection is called.
struct dunstblick_Connection DOXYGEN_BODY;

/// @brief A temporary object handle for bulk property updates.
/// Is created by @ref dunstblick_BeginChangeObject and must be destroyed
/// bei **either** @ref dunstblick_CommitObject **or** @ref dunstblick_CancelObject.
struct dunstblick_Object DOXYGEN_BODY;

enum dunstblick_EventType {
  DUNSTBLICK_EVENT_NONE = 0,
  DUNSTBLICK_EVENT_CONNECTED = 1,
  DUNSTBLICK_EVENT_DISCONNECTED = 2,
  DUNSTBLICK_EVENT_WIDGET = 3,
  DUNSTBLICK_EVENT_PROPERTY_CHANGED = 4,

};

struct dunstblick_ConnectedEvent {
  uint16_t type;

    struct dunstblick_Connection * connection;
    struct dunstblick_Size screen_size;
    uint32_t capabilities; // : std.EnumSet(ClientCapabilities),
};

struct dunstblick_DisconnectedEvent {
  uint16_t type;

  struct dunstblick_Connection *connection;
  uint32_t reason;
};

struct dunstblick_WidgetEvent {
  uint16_t type;

  struct dunstblick_Connection * connection;
  dunstblick_EventID event;
  dunstblick_WidgetName caller;
};

struct dunstblick_PropertyChangedEvent {
  uint16_t type;

  struct dunstblick_Connection*   connection;
  dunstblick_ObjectID object;
  dunstblick_PropertyName property;
  struct dunstblick_Value value;
};

union dunstblick_Event {
  uint16_t type;
  struct dunstblick_ConnectedEvent connected;
  struct dunstblick_DisconnectedEvent disconnected;
  struct dunstblick_WidgetEvent widget_event;
  struct dunstblick_PropertyChangedEvent property_changed;
};

// Provider Functions:

/// Creates a new UI provider that will respond to dunstblick search requests.
/// If a user wants to connect to this application, the *Connected* callback
/// is called.
struct dunstblick_Provider *dunstblick_OpenProvider(
    char const *discoveryName,   ///< The name of the application which will be broadcasted
    char const *app_description, ///< Optional description of the application.
    unsigned char const *app_icon_ptr,    ///< Optional ptr to a TVG icon
    size_t app_icon_len          ///< Length of `app_icon_ptr` or 0.
);

/// Shuts down the ui provider and closes all open connections.
void dunstblick_CloseProvider(struct dunstblick_Provider *provider);



/// Pumps network data. Returns `DUNSTBLICK_ERROR_GOT_EVENT` if a event was received and put into `event`.
/// Call this function continuously to provide a fluent user interaction and prevent network timeouts.
/// @remarks Same as @ref dunstblick_WaitEvent, but does not block.
enum dunstblick_Error dunstblick_PumpEvents(struct dunstblick_Provider *provider, union dunstblick_Event * event);

/// Waits for a network event. Cannot return `DUNSTBLICK_ERROR_NONE`
/// @remarks Same as @ref dunstblick_PumpEvents, but blocks until some event or network activity happens.
enum dunstblick_Error dunstblick_WaitEvent(struct dunstblick_Provider *provider, union dunstblick_Event * event);

/// Adds a resource to the UI system.
/// The resource will be hashed and stored until the provider is shut down
/// or the the resource is removed again.
/// Resources in the storage will be uploaded to a display client on connection
/// and newly added resources will also be sent to all currently connected display
/// clients.
enum dunstblick_Error dunstblick_AddResource(
    struct dunstblick_Provider *provider, ///< The ui provider that will receive the resource.
    dunstblick_ResourceID resourceID,     ///< The ID of the resource
    enum dunstblick_ResourceKind type,    ///< Specifies the type of the resource data.
    void const *data,                     ///< Pointer to resource data. The encoding of the data is defined by `type`.
    uint32_t length                       ///< Size of the resource in bytes.
);

/// Deletes a resource from the UI system.
/// Already uploaded resources will stay uploaded until the resource ID is
/// used again, but newly connected display clients will not receive the
/// resource anymore.
enum dunstblick_Error dunstblick_RemoveResource(
    struct dunstblick_Provider *provider, ///< The ui provider that will receive the resource.
    dunstblick_ResourceID resourceID      ///< ID of the resource that will be removed.
);

/// Returns the current number of connected display clients.
size_t dunstblick_GetConnectionCount(struct dunstblick_Provider *provider);

/// Returns one of the currently established connections.
/// Returns `NULL` if the connection is not valid.
struct dunstblick_Connection *dunstblick_GetConnection(struct dunstblick_Provider *provider,
                                                       size_t index ///< The index of the connection.
);

// Connection functions:

/// Closes the connection and disconnects the display client.
void dunstblick_CloseConnection(struct dunstblick_Connection *connection, ///< The connection to be closed.
                                char const *reason                        ///< The disconnect reason that will be displayed to the client.
                                                                          ///< May be `NULL`, then no reason is displayed to the client.
);

/// Stores a custom pointer in the connection handle.
/// This can be used to associate a custom state with the connection
/// that can be freed in @ref dunstblick_DisconnectedCallback.
void dunstblick_SetUserData(
    struct dunstblick_Connection *connection, ///< The connection for which the user data should be set.
    void *userData                            ///< The pointer that should be associated with the connection.
);

/// Returns a previously associated user data for this connection.
/// @returns The previously associated pointer or `NULL` if none was set.
void *dunstblick_GetUserData(
    struct dunstblick_Connection *connection ///< The connection for which the user data should be queried.
);

/// Returns the name of the display client.
char const *dunstblick_GetClientName(struct dunstblick_Connection *connection);

/// Gets the current display size of the client.
struct dunstblick_Size dunstblick_GetDisplaySize(struct dunstblick_Connection *connection);

/// Starts an object change. This is similar to a SQL transaction:
/// - the change process is initiated
/// - changes are made to an object handle
/// - the process is either commited or cancelled.
///
/// @returns Handle to the object that should be updated. Commit or cancel this handle to finalize this transaction.
/// @see dunstblick_CommitObject, dunstblick_CancelObject, dunstblick_SetObjectProperty
struct dunstblick_Object *dunstblick_BeginChangeObject(
    struct dunstblick_Connection *, ///< The connection where the action should be applied.
    dunstblick_ObjectID id);

/// Removes a previously uploaded object.
enum dunstblick_Error dunstblick_RemoveObject(
    struct dunstblick_Connection *, ///< The connection where the action should be applied.
    dunstblick_ObjectID             ///< The id of the object that should be removed.
);

/// Sets the current view.
/// This view must have been uploaded with @ref dunstblick_UploadResource earlier.
enum dunstblick_Error dunstblick_SetView(struct dunstblick_Connection *, ///< The connection where the action should be applied.
                                         dunstblick_ResourceID           ///< id of the layout resource that should be displayed
);

/// Sets the current binding root.
/// This object will serve as the root of all binding functions and will provide
/// the root logic for the current view.
enum dunstblick_Error dunstblick_SetRoot(struct dunstblick_Connection *, ///< The connection where the action should be applied.
                                         dunstblick_ObjectID             ///< id of the object that will be root.
);

/// Changes a property of an object.
enum dunstblick_Error dunstblick_SetProperty(
    struct dunstblick_Connection *,      ///< The connection where the action should be applied.
    dunstblick_ObjectID,                 ///< id of the object
    dunstblick_PropertyName,             ///< name of the property
    struct dunstblick_Value const *value ///< new value of the property. must fit the previously uploaded type!
);                                       // "unsafe command", uses the serverside object type or fails of property does not exist

/// Clears a list property of an object.
/// This action will remove all object references from an objectlist property.
enum dunstblick_Error dunstblick_Clear(struct dunstblick_Connection *, ///< The connection where the action should be applied.
                                       dunstblick_ObjectID,            ///< target object
                                       dunstblick_PropertyName         ///< target property
);

/// Inserts a given range of object references into a list property.
enum dunstblick_Error dunstblick_InsertRange(
    struct dunstblick_Connection *,   ///< The connection where the action should be applied.
    dunstblick_ObjectID,              ///< target object
    dunstblick_PropertyName,          ///< target property
    uint32_t index,                   ///< start index of insertion
    uint32_t count,                   ///< number of object references to insert.
    dunstblick_ObjectID const *values ///< Pointer to an array of object IDs that should be inserted into the list.
);

/// Removes a given range from a list property.
enum dunstblick_Error dunstblick_RemoveRange(
    struct dunstblick_Connection *, ///< The connection where the action should be applied.
    dunstblick_ObjectID,            ///< target object
    dunstblick_PropertyName,        ///< target property
    uint32_t index,                 ///< first index of the object references to be removed.
    uint32_t count                  ///< number of references that should be removed
);

/// Moves a given range in a list property.
/// This action is currently not implemented due to underspecification.
enum dunstblick_Error dunstblick_MoveRange(
    struct dunstblick_Connection *, ///< The connection where the action should be applied.
    dunstblick_ObjectID,            ///< target object
    dunstblick_PropertyName,        ///< target property
    uint32_t indexFrom,
    uint32_t indexTo,
    uint32_t count);

// Object functions:

/// Sets a property on the given object.
/// The third parameter depends on the given type parameter.
enum dunstblick_Error dunstblick_SetObjectProperty(struct dunstblick_Object *,          ///< object of which a property should be set.
                                                   dunstblick_PropertyName,             ///< name of the property
                                                   struct dunstblick_Value const *value ///< the value of the property
);

/// The object will either be added to the list of objects
/// or, if an object with the same ID already exists, will replace that object.
/// The new object will only have the properties set in this transaction,
/// all old properties will be __removed__.
/// @remarks the object will be released in this function. the handle is not valid after this function is called.
enum dunstblick_Error dunstblick_CommitObject(struct dunstblick_Object *);

/// Closes the object and cancels the update process.
/// @remarks the object will be released in this function. the handle is not valid after this function is called.
void dunstblick_CancelObject(struct dunstblick_Object *);

#ifndef DUNSTBLICK_NO_GLOBAL_NAMESPACE
typedef struct dunstblick_Provider dunstblick_Provider;
typedef struct dunstblick_Connection dunstblick_Connection;
typedef struct dunstblick_Object dunstblick_Object;

typedef struct dunstblick_Value dunstblick_Value;
typedef struct dunstblick_ConnectedEvent dunstblick_ConnectedEvent;
typedef struct dunstblick_DisconnectedEvent dunstblick_DisconnectedEvent;
typedef struct dunstblick_WidgetEvent dunstblick_WidgetEvent;
typedef struct dunstblick_PropertyChangedEvent dunstblick_PropertyChangedEvent;
typedef union dunstblick_Event dunstblick_Event;

typedef struct dunstblick_Color dunstblick_Color;
typedef struct dunstblick_Point dunstblick_Point;
typedef struct dunstblick_Size dunstblick_Size;
typedef struct dunstblick_Margins dunstblick_Margins;

typedef enum dunstblick_DisconnectReason dunstblick_DisconnectReason;
typedef enum dunstblick_Error dunstblick_Error;

typedef enum dunstblick_ClientCapabilities dunstblick_ClientCapabilities;
typedef enum dunstblick_Type dunstblick_Type;
typedef enum dunstblick_ResourceKind dunstblick_ResourceKind;

#endif // DUNSTBLICK_NO_GLOBAL_NAMESPACE

#ifdef __cplusplus
}
#endif

#endif // DUNSTBLICK2_H
