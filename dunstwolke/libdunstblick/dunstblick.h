#ifndef DUNSTBLICK_H
#define DUNSTBLICK_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum dunstblick_ResourceKind
{
	DUNSTBLICK_RESOURCE_LAYOUT  = 0,
	DUNSTBLICK_RESOURCE_BITMAP  = 1,
	DUNSTBLICK_RESOURCE_DRAWING = 2,
} dunstblick_ResourceKind;

typedef enum dunstblick_Type
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
} dunstblick_Type;

typedef enum dunstblick_Error
{
	DUNSTBLICK_ERROR_NONE = 0,
	DUNSTBLICK_ERROR_INVALID_ARG = 1,
	DUNSTBLICK_ERROR_NETWORK = 2,
	DUNSTBLICK_ERROR_INVALID_TYPE = 3,
} dunstblick_Error;

typedef uint32_t dunstblick_ResourceID;
typedef uint32_t dunstblick_ObjectID;
typedef uint32_t dunstblick_PropertyName;
typedef uint32_t dunstblick_CallbackID;

typedef struct dunstblick_Color {
	uint8_t r, g, b, a;
} dunstblick_Color;

typedef struct dunstblick_Point {
	int x, y;
} dunstblick_Point;

typedef struct dunstblick_Size {
	int w, h;
} dunstblick_Size;

typedef struct dunstblick_Margins {
	int left, top, right, bottom;
} dunstblick_Margins;

typedef struct dunstblick_Value
{
	dunstblick_Type type;
	union {
		int integer;
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
	};
} dunstblick_Value;

typedef struct dunstblick_Connection dunstblick_Connection;

typedef struct dunstblick_Object dunstblick_Object;

typedef struct dunstblick_EventHandler {
	void (*onCallback)(dunstblick_CallbackID cid, void * context);
	void (*onPropertyChanged)(dunstblick_ObjectID oid, dunstblick_PropertyName property, dunstblick_Value const * value);
} dunstblick_EventHandler;

/*******************************************************************************
* Connection API
*******************************************************************************/

/// Opens a connection to a dunstblick server.
/// @returns pointer to a connection handle
dunstblick_Connection * dunstblick_Open(
	char const * host, ///< Host name or address of the dunstblick server
	int portNumber     ///< Port number of the dunstblick server. Usually 1309
);

/// Pumps incoming events from the connection.
/// This allows synchronous event handling with the calling thread.
dunstblick_Error dunstblick_PumpEvents(
	dunstblick_Connection *, ///< The connection for which events should be pumped.
	dunstblick_EventHandler const *, ///< The event pump that will receive the pumped events.
	void * context           ///< Custom parameter that will be passed to the event handler
);


/// Closes an established connection to a dunstblick server.
void dunstblick_Close(
	dunstblick_Connection * ///< The connection that should be closed.
);


/*******************************************************************************
* Client-To-Server API
*******************************************************************************/

/// Uploads a certain resource to the server.
dunstblick_Error dunstblick_UploadResource(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ResourceID,   ///< The unique identifier of this resource.
	dunstblick_ResourceKind, ///< The kind of resource this is.
	void const * data,       ///< A non-null pointer to the data that should be uploaded
	size_t length            ///< The length of the data in bytes.
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
	dunstblick_ObjectID id
);

/// Removes a previously uploaded object.
dunstblick_Error dunstblick_RemoveObject(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID      ///< The id of the object that should be removed.
);

/// Sets the current view.
/// This view must have been uploaded with @ref dunstblick_UploadResource earlier.
dunstblick_Error dunstblick_SetView(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ResourceID    ///< id of the layout resource that should be displayed
);

/// Sets the current binding root.
/// This object will serve as the root of all binding functions and will provide
/// the root logic for the current view.
dunstblick_Error dunstblick_SetRoot(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID      ///< id of the object that will be root.
);

/// Changes a property of an object.
dunstblick_Error dunstblick_SetProperty(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID,     ///< id of the object
	dunstblick_PropertyName, ///< name of the property
	dunstblick_Value const * value ///< new value of the property. must fit the previously uploaded type!
); // "unsafe command", uses the serverside object type or fails of property does not exist

/// Clears a list property of an object.
/// This action will remove all object references from an objectlist property.
dunstblick_Error dunstblick_Clear(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID,     ///< target object
	dunstblick_PropertyName ///< target property
);

/// Inserts a given range of object references into a list property.
dunstblick_Error dunstblick_InsertRange(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID,     ///< target object
	dunstblick_PropertyName, ///< target property
	size_t index,            ///< start index of insertion
	size_t count,            ///< number of object references to insert.
	dunstblick_ObjectID const * values ///< Pointer to an array of object IDs that should be inserted into the list.
);

/// Removes a given range from a list property.
dunstblick_Error dunstblick_RemoveRange(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID,     ///< target object
	dunstblick_PropertyName, ///< target property
	size_t index,            ///< first index of the object references to be removed.
	size_t count             ///< number of references that should be removed
);

/// Moves a given range in a list property.
/// This action is currently not implemented due to underspecification.
dunstblick_Error dunstblick_MoveRange(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ObjectID,     ///< target object
	dunstblick_PropertyName, ///< target property
	size_t indexFrom,
	size_t indexTo,
	size_t count
);


/*******************************************************************************
* Object Write API
*******************************************************************************/

/// Sets a property on the given object.
/// The third parameter depends on the given type parameter.
dunstblick_Error  dunstblick_SetObjectProperty(
	dunstblick_Object *,           ///< object of which a property should be set.
	dunstblick_PropertyName,       ///< name of the property
	dunstblick_Value const * value ///< the value of the property
);

/// The object will either be added to the list of objects
/// or, if an object with the same ID already exists, will replace that object.
/// The new object will only have the properties set in this transaction,
/// all old properties will be __removed__.
/// @remarks the object will be released in this function. the handle is not valid after this function is called.
dunstblick_Error dunstblick_CommitObject(
	dunstblick_Object *
);

/// Closes the object and cancels the update process.
/// @remarks the object will be released in this function. the handle is not valid after this function is called.
void dunstblick_CancelObject(
	dunstblick_Object *
);


#ifdef __cplusplus
}
#endif

#endif // DUNSTBLICK_H
