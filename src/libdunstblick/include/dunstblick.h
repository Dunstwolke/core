#ifndef DUNSTBLICK2_H
#define DUNSTBLICK2_H

/// @file
/// @brief This module contains the API of the @ref dunstblick user interface.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// @brief Enumeration of all available resource types.
    enum dunstblick_ResourceKind
    {
        /// A layout resource contains the compiled description of a widget layout.
        /// Create a compiled layout with the @ref dunstblick-compiler.
        DUNSTBLICK_RESOURCE_LAYOUT = 0,
        /// A raster image resource that contains a common image file like PNG or JPEG.
        DUNSTBLICK_RESOURCE_BITMAP = 1,
        /// A vector image resource that contains a yet unspecified format.
        DUNSTBLICK_RESOURCE_DRAWING = 2,
    };
    typedef enum dunstblick_ResourceKind dunstblick_ResourceKind;

    /// @brief Contains a type tag for each possible type a @ref dunstblick_Value can have.
    enum dunstblick_Type
    {
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
        DUNSTBLICK_TYPE_NAME = 15,
    };
    typedef enum dunstblick_Type dunstblick_Type;

    /// @brief Feature flags the display client capabilities.
    /// These flags can be used to decide what UI layouts to deliver to the client.
    enum dunstblick_ClientCapabilities
    {
        DUNSTBLICK_CAPS_NONE = 0,     ///< The client has no special capabilities.
        DUNSTBLICK_CAPS_MOUSE = 1,    ///< The client has a mouse available.
        DUNSTBLICK_CAPS_KEYBOARD = 2, ///< The client has a keyboard available.
        DUNSTBLICK_CAPS_TOUCH = 4,    ///< The client has a touchscreen available.
        DUNSTBLICK_CAPS_HIGHDPI = 8,  ///< The client has a high-dpi screen
        DUNSTBLICK_CAPS_TILTABLE =
            16, ///< The client can be tilted and switch between portrait and landscape view (like a mobile device)
        DUNSTBLICK_CAPS_RESIZABLE = 32, ///< The client area can be resized (for example when it's hosted in a window
                                        ///< instead of a fullscreen application)
        DUNSTBLICK_CAPS_REQ_ACCESSIBILITY = 64, ///< The client wants to have a special UI for improved accessiblity
    };
    typedef enum dunstblick_ClientCapabilities dunstblick_ClientCapabilities;

    /// @brief Error codes that are returned by a function.
    enum dunstblick_Error
    {
        DUNSTBLICK_ERROR_NONE = 0,                  ///< The operation was successful.
        DUNSTBLICK_ERROR_INVALID_ARG = 1,           ///< An invalid argument was passed to the function.
        DUNSTBLICK_ERROR_NETWORK = 2,               ///< A network error happened.
        DUNSTBLICK_ERROR_INVALID_TYPE = 3,          ///< An invalid type was passed to a function.
        DUNSTBLICK_ERROR_ARGUMENT_OUT_OF_RANGE = 4, ///< An argument was not in the allowed range.
        DUNSTBLICK_ERROR_OUT_OF_MEMORY = 5,         ///< An allocation failed.
        DUNSTBLICK_ERROR_RESOURCE_NOT_FOUND = 6,    ///< A requested resource was not found.
    };
    typedef enum dunstblick_Error dunstblick_Error;

    /// @brief Enumeration of possible reasons for a client disconnection.
    enum dunstblick_DisconnectReason
    {
        DUNSTBLICK_DISCONNECT_QUIT = 0,
        DUNSTBLICK_DISCONNECT_SHUTDOWN = 1,
        DUNSTBLICK_DISCONNECT_TIMEOUT = 2,
        DUNSTBLICK_DISCONNECT_NETWORK_ERROR = 3,
        DUNSTBLICK_DISCONNECT_INVALID_DATA = 4,
        DUNSTBLICK_DISCONNECT_PROTOCOL_MISMATCH = 5,
    };
    typedef enum dunstblick_DisconnectReason dunstblick_DisconnectReason;

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
    struct dunstblick_Color
    {
        uint8_t r; ///< Red color channel
        uint8_t g; ///< Green color channel
        uint8_t b; ///< Blue color channel
        uint8_t a; ///< Transparency channel. 128 is 50% alpha
    };
    typedef struct dunstblick_Color dunstblick_Color;

    /// @brief 2D point in screen space coordinates.
    struct dunstblick_Point
    {
        int32_t x; ///< distance to the left screen border
        int32_t y; ///< distance to the upper screen border
    };
    typedef struct dunstblick_Point dunstblick_Point;

    /// @brief 2D dimensions.
    struct dunstblick_Size
    {
        uint32_t w; ///< Horizontal extends.
        uint32_t h; ///< Vertical extends.
    };
    typedef struct dunstblick_Size dunstblick_Size;

    /// @brief Width of margins of a rectangle.
    struct dunstblick_Margins
    {
        uint32_t left, top, right, bottom;
    };
    typedef struct dunstblick_Margins dunstblick_Margins;

    /// @brief A type-tagged value for the dunstblick API.
    struct dunstblick_Value
    {
        dunstblick_Type type; ///< Type of the value. The union field corresponding to this field is active.
        union
        {
            int32_t integer;
            uint8_t enumeration;
            float number;
            char const * string;
            dunstblick_ResourceID resource;
            dunstblick_ObjectID object;
            dunstblick_Color color;
            dunstblick_Size size;
            dunstblick_Point point;
            dunstblick_Margins margins;
            bool boolean;
            dunstblick_EventID event;
            dunstblick_PropertyName name;
        } value;
    };
    typedef struct dunstblick_Value dunstblick_Value;

    // Opaque Types:

#ifdef ONLY_FOR_DOXYGEN
#define DOXYGEN_BODY                                                                                                   \
    {}
#else
#define DOXYGEN_BODY
#endif

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

    typedef struct dunstblick_Provider dunstblick_Provider;
    typedef struct dunstblick_Connection dunstblick_Connection;
    typedef struct dunstblick_Object dunstblick_Object;

    // Callback Types:

    /// @brief A callback that is called whenever a new display client has successfully
    ///        connected to the display provider.
    /// It's possible to disconnect the client in this callback, the @ref dunstblick_DisconnectedCallback
    /// will be called as soon as this function returns.
    typedef void (*dunstblick_ConnectedCallback)(
        dunstblick_Provider * provider,     ///< The provider to which the connection was established.
        dunstblick_Connection * connection, ///< The newly created connection.
        char const * clientName,            ///< The name of the display client. If none is given, it's just `IP:port`
        char const * password,              ///< The password that was passed by the user.
        dunstblick_Size screenSize,         ///< Current screen size of the display client.
        dunstblick_ClientCapabilities
            capabilities, ///< Bitmask containing all available capabilities of the display client.
        void * userData   ///< The user data pointer that was passed to @ref dunstblick_SetConnectedCallback.
    );

    /// @brief A callback that is called whenever a display client has disconnected
    ///        from the provider.
    /// This callback is called for every disconnected client, even when the client is closed
    /// in the @ref dunstblick_ConnectedCallback.
    /// @remarks It is possible to query information about `connection`, but it's not possible
    ///          anymore to send any data to it.
    typedef void (*dunstblick_DisconnectedCallback)(
        dunstblick_Provider * provider,     ///< The provider from which the connection was established.
        dunstblick_Connection * connection, /// The connection that is about to be closed.
        dunstblick_DisconnectReason reason, ///< The reason why the  display client is disconnected
        void * userData ///< The user data pointer that was passed to @ref dunstblick_SetDisconnectedCallback.
    );

    /// @brief A callback that is called whenever a display client triggers a event.
    typedef void (*dunstblick_EventCallback)(
        dunstblick_Connection * connection, ///< the display client that triggered the event.
        dunstblick_EventID callback, ///< The id of the event that was triggered. This ID is specified in the UI layout.
        dunstblick_WidgetName caller, ///< The name of the widget that triggered the event.
        void * userData               ///< The user data pointer that was passed to @ref dunstblick_SetEventCallback.
    );

    /// @brief A callbcak that is called whenever a display client changed the property of an object.
    typedef void (*dunstblick_PropertyChangedCallback)(
        dunstblick_Connection * connection, ///< the display client that changed the event.
        dunstblick_ObjectID object,         ///< The object handle where the property was changed
        dunstblick_PropertyName property,   ///< The name of the property that was changed
        dunstblick_Value const * value,     ///< The value of the property
        void * userData ///< The user data pointer that was passed to @ref dunstblick_SetPropertyChangedCallback.
    );

    // Provider Functions:

    /// Creates a new UI provider that will respond to dunstblick search requests.
    /// If a user wants to connect to this application, the *Connected* callback
    /// is called.
    dunstblick_Provider * dunstblick_OpenProvider(
        char const * discoveryName, ///< The name of the application which will be broadcasted
        char const * app_description, ///< Optional description of the application.
        char const * app_icon_ptr, ///< Optional ptr to a TVG icon
        size_t       app_icon_len ///< Length of `app_icon_ptr` or 0.
    );

    /// Shuts down the ui provider and closes all open connections.
    void dunstblick_CloseProvider(dunstblick_Provider * provider);

    /// Pumps network data, calls connection events and disconnect/connect callbacks.
    /// Call this function continuously to provide a fluent user interaction
    /// and prevent network timeouts.
    /// @remarks Same as @ref dunstblick_PumpEvents, but does not block.
    dunstblick_Error dunstblick_PumpEvents(dunstblick_Provider * provider);

    /// Pumps network data, calls connection events and disconnect/connect callbacks.
    /// Call this function continuously to provide a fluent user interaction
    /// and prevent network timeouts.
    /// @remarks Same as @ref dunstblick_PumpEvents, but blocks until some event or network activity happens.
    dunstblick_Error dunstblick_WaitEvents(dunstblick_Provider * provider);

    /// Adds a resource to the UI system.
    /// The resource will be hashed and stored until the provider is shut down
    /// or the the resource is removed again.
    /// Resources in the storage will be uploaded to a display client on connection
    /// and newly added resources will also be sent to all currently connected display
    /// clients.
    dunstblick_Error dunstblick_AddResource(
        dunstblick_Provider * provider,   ///< The ui provider that will receive the resource.
        dunstblick_ResourceID resourceID, ///< The ID of the resource
        dunstblick_ResourceKind type,     ///< Specifies the type of the resource data.
        void const * data,                ///< Pointer to resource data. The encoding of the data is defined by `type`.
        uint32_t length                   ///< Size of the resource in bytes.
    );

    /// Deletes a resource from the UI system.
    /// Already uploaded resources will stay uploaded until the resource ID is
    /// used again, but newly connected display clients will not receive the
    /// resource anymore.
    dunstblick_Error dunstblick_RemoveResource(
        dunstblick_Provider * provider,  ///< The ui provider that will receive the resource.
        dunstblick_ResourceID resourceID ///< ID of the resource that will be removed.
    );

    /// Sets the callback that will be called when a new display client connects.
    dunstblick_Error dunstblick_SetConnectedCallback(
        dunstblick_Provider * provider,
        dunstblick_ConnectedCallback callback, ///< Either a callback or `NULL` of the callback should be disabled.
        void * userData                        ///< User data will be stored and passed to the callback.
    );

    /// Sets the callback that will be called when a display client disconnects.
    dunstblick_Error dunstblick_SetDisconnectedCallback(
        dunstblick_Provider * provider,
        dunstblick_DisconnectedCallback callback, ///< Either a callback or `NULL` of the callback should be disabled.
        void * userData                           ///< User data will be stored and passed to the callback.
    );

    /// Returns the current number of connected display clients.
    size_t dunstblick_GetConnectionCount(dunstblick_Provider * provider);

    /// Returns one of the currently established connections.
    /// Returns `NULL` if the connection is not valid.
    dunstblick_Connection * dunstblick_GetConnection(dunstblick_Provider * provider,
                                                     size_t index ///< The index of the connection.
    );

    // Connection functions:

    /// Closes the connection and disconnects the display client.
    void dunstblick_CloseConnection(dunstblick_Connection * connection, ///< The connection to be closed.
                                    char const * reason ///< The disconnect reason that will be displayed to the client.
                                                        ///< May be `NULL`, then no reason is displayed to the client.
    );

    /// Stores a custom pointer in the connection handle.
    /// This can be used to associate a custom state with the connection
    /// that can be freed in @ref dunstblick_DisconnectedCallback.
    void dunstblick_SetUserData(
        dunstblick_Connection * connection, ///< The connection for which the user data should be set.
        void * userData                     ///< The pointer that should be associated with the connection.
    );

    /// Returns a previously associated user data for this connection.
    /// @returns The previously associated pointer or `NULL` if none was set.
    void * dunstblick_GetUserData(
        dunstblick_Connection * connection ///< The connection for which the user data should be queried.
    );

    /// Returns the name of the display client.
    char const * dunstblick_GetClientName(dunstblick_Connection * connection);

    /// Gets the current display size of the client.
    dunstblick_Size dunstblick_GetDisplaySize(dunstblick_Connection * connection);

    /// Sets the callback that will be called when the display client
    /// invokes an UI event.
    void dunstblick_SetEventCallback(
        dunstblick_Connection * connection, ///< The connection for which the callback should be set.
        dunstblick_EventCallback callback,  ///< The callback that will be called when an UI event happens.
        void * userData                     ///< A pointer that will be stored and be passed to the callback.
    );

    /// Sets the callback that will be called when the display client
    /// changes an object property.
    void dunstblick_SetPropertyChangedCallback(
        dunstblick_Connection * connection,          ///< The connection for which the callback should be set.
        dunstblick_PropertyChangedCallback callback, ///< The callback that will be called when an UI event happens.
        void * userData                              ///< A pointer that will be stored and be passed to the callback.
    );

    /// Starts an object change. This is similar to a SQL transaction:
    /// - the change process is initiated
    /// - changes are made to an object handle
    /// - the process is either commited or cancelled.
    ///
    /// @returns Handle to the object that should be updated. Commit or cancel this handle to finalize this transaction.
    /// @see dunstblick_CommitObject, dunstblick_CancelObject, dunstblick_SetObjectProperty
    dunstblick_Object * dunstblick_BeginChangeObject(
        dunstblick_Connection *, ///< The connection where the action should be applied.
        dunstblick_ObjectID id);

    /// Removes a previously uploaded object.
    dunstblick_Error dunstblick_RemoveObject(
        dunstblick_Connection *, ///< The connection where the action should be applied.
        dunstblick_ObjectID      ///< The id of the object that should be removed.
    );

    /// Sets the current view.
    /// This view must have been uploaded with @ref dunstblick_UploadResource earlier.
    dunstblick_Error dunstblick_SetView(dunstblick_Connection *, ///< The connection where the action should be applied.
                                        dunstblick_ResourceID    ///< id of the layout resource that should be displayed
    );

    /// Sets the current binding root.
    /// This object will serve as the root of all binding functions and will provide
    /// the root logic for the current view.
    dunstblick_Error dunstblick_SetRoot(dunstblick_Connection *, ///< The connection where the action should be applied.
                                        dunstblick_ObjectID      ///< id of the object that will be root.
    );

    /// Changes a property of an object.
    dunstblick_Error dunstblick_SetProperty(
        dunstblick_Connection *,       ///< The connection where the action should be applied.
        dunstblick_ObjectID,           ///< id of the object
        dunstblick_PropertyName,       ///< name of the property
        dunstblick_Value const * value ///< new value of the property. must fit the previously uploaded type!
    ); // "unsafe command", uses the serverside object type or fails of property does not exist

    /// Clears a list property of an object.
    /// This action will remove all object references from an objectlist property.
    dunstblick_Error dunstblick_Clear(dunstblick_Connection *, ///< The connection where the action should be applied.
                                      dunstblick_ObjectID,     ///< target object
                                      dunstblick_PropertyName  ///< target property
    );

    /// Inserts a given range of object references into a list property.
    dunstblick_Error dunstblick_InsertRange(
        dunstblick_Connection *,           ///< The connection where the action should be applied.
        dunstblick_ObjectID,               ///< target object
        dunstblick_PropertyName,           ///< target property
        uint32_t index,                    ///< start index of insertion
        uint32_t count,                    ///< number of object references to insert.
        dunstblick_ObjectID const * values ///< Pointer to an array of object IDs that should be inserted into the list.
    );

    /// Removes a given range from a list property.
    dunstblick_Error dunstblick_RemoveRange(
        dunstblick_Connection *, ///< The connection where the action should be applied.
        dunstblick_ObjectID,     ///< target object
        dunstblick_PropertyName, ///< target property
        uint32_t index,          ///< first index of the object references to be removed.
        uint32_t count           ///< number of references that should be removed
    );

    /// Moves a given range in a list property.
    /// This action is currently not implemented due to underspecification.
    dunstblick_Error dunstblick_MoveRange(
        dunstblick_Connection *, ///< The connection where the action should be applied.
        dunstblick_ObjectID,     ///< target object
        dunstblick_PropertyName, ///< target property
        uint32_t indexFrom,
        uint32_t indexTo,
        uint32_t count);

    // Object functions:

    /// Sets a property on the given object.
    /// The third parameter depends on the given type parameter.
    dunstblick_Error dunstblick_SetObjectProperty(dunstblick_Object *, ///< object of which a property should be set.
                                                  dunstblick_PropertyName,       ///< name of the property
                                                  dunstblick_Value const * value ///< the value of the property
    );

    /// The object will either be added to the list of objects
    /// or, if an object with the same ID already exists, will replace that object.
    /// The new object will only have the properties set in this transaction,
    /// all old properties will be __removed__.
    /// @remarks the object will be released in this function. the handle is not valid after this function is called.
    dunstblick_Error dunstblick_CommitObject(dunstblick_Object *);

    /// Closes the object and cancels the update process.
    /// @remarks the object will be released in this function. the handle is not valid after this function is called.
    void dunstblick_CancelObject(dunstblick_Object *);

#ifdef __cplusplus
}
#endif

#endif // DUNSTBLICK2_H
