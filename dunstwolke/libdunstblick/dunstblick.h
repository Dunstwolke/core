#ifndef DUNSTBLICK_H
#define DUNSTBLICK_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

enum dunstblick_ResourceKind
{
	DUNSTBLICK_RESOURCE_LAYOUT  = 0,
	DUNSTBLICK_RESOURCE_BITMAP  = 1,
	DUNSTBLICK_RESOURCE_DRAWING = 2,
};

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
	DUNSTBLICK_TYPE_SIZELIST = 11,
	DUNSTBLICK_TYPE_OBJECT = 12,
	DUNSTBLICK_TYPE_OBJECTLIST = 13,
};

enum dunstblick_Error
{
	DUNSTBLICK_ERROR_NONE = 0,
};

typedef uint32_t dunstblick_ResourceID;
typedef uint32_t dunstblick_ObjectID;
typedef uint32_t dunstblick_PropertyName;

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
	};
} dunstblick_Value;

typedef struct dunstblick_Connection dunstblick_Connection;

// basic API

/// Opens a connection to a dunstblick server.
/// @returns pointer to a connection handle
dunstblick_Connection * dunstblick_Open(
	char const * host, ///< Host name or address of the dunstblick server
	int portNumber     ///< Port number of the dunstblick server. Usually 1309
);

/// Closes an established connection to a dunstblick server.
void dunstblick_Close(
	dunstblick_Connection * ///< The connection that should be closed.
);

// client-to-server API

/// Uploads a certain resource to the server.
dunstblick_Error dunstblick_UploadResource(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	dunstblick_ResourceID,   ///< The unique identifier of this resource.
	dunstblick_ResourceKind, ///< The kind of resource this is.
	void const * data,       ///< A non-null pointer to the data that should be uploaded
	size_t length            ///< The length of the data in bytes.
);

/// Uploads an object. The object will either be added to the list of objects
/// or, if an object with the same ID already exists, will replace that object.
dunstblick_Error dunstblick_AddOrUpdateObject(
	dunstblick_Connection *, ///< The connection where the action should be applied.
	obj
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
); // manipulate lists

#ifdef __cplusplus
}
#endif

#endif // DUNSTBLICK_H
