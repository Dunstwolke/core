#include <stdio.h>
#include <stdlib.h>

#include <dunstblick.h>
#include <unistd.h>

#define OBJ_ROOT 1
#define PROP_RESULT 1

#define DBCHECKED(_X) do { \
		dunstblick_Error err = _X; \
		if(err != DUNSTBLICK_ERROR_NONE) \
		{ \
			printf("failed to execute " #_X ": %d\n", err); \
			return 1; \
		} \
	} while(0)

bool load_file(char const * fileName, void ** buffer, size_t * len)
{
	*buffer = NULL;
	*len = 0;

	FILE * f = fopen(fileName, "rb");
	if(f == NULL)
		return false;
	fseek(f, 0, SEEK_END);
	*len = ftell(f);
	fseek(f, 0, SEEK_SET);

	*buffer = malloc(*len);

	size_t offset = 0;
	while(offset < *len)
	{
		ssize_t delta = fread((char*)*buffer + offset, 1, *len - offset, f);
		if(delta < 0) {
			free(*buffer);
			*buffer = NULL;
			*len = 0;
			fclose(f);
			return false;
		}
		offset += delta;
	}

	fclose(f);

	return true;
}

void onCallback(dunstblick_CallbackID cid, void * context)
{
	printf("got callback: %d\n", cid);
	fflush(stdout);
}

void onPropertyChanged(dunstblick_ObjectID oid, dunstblick_PropertyName property, dunstblick_Value const * value)
{
	printf("property changed: oid=%d, property=%d, value(type)=%d\n", oid, property, value->type);
}

int main()
{
	void * root_layout;
	size_t root_layout_size;

	if(!load_file("calculator-ui.bin", &root_layout, &root_layout_size)) {
		printf("failed to load layout file!\n");
		return 1;
	}

	dunstblick_EventHandler events = {
		.onCallback = &onCallback,
		.onPropertyChanged = &onPropertyChanged,
	};

	dunstblick_Connection * con = dunstblick_Open("127.0.0.1", 1309);
	if(con == NULL) {
		printf("Failed to establish connection!\n");
		return 1;
	}

	DBCHECKED(dunstblick_UploadResource(con, 1, DUNSTBLICK_RESOURCE_LAYOUT, root_layout, root_layout_size));

	{
		dunstblick_Object * root_obj = dunstblick_AddOrUpdateObject(con, OBJ_ROOT);
		if(root_obj == NULL) {
			printf("failed to create object!\n");
			return 1;
		}
		dunstblick_Value result = {
		    .type = DUNSTBLICK_TYPE_STRING,
		    .string = "0",
		};

		DBCHECKED(dunstblick_SetObjectProperty(root_obj, PROP_RESULT, &result));
		DBCHECKED(dunstblick_CloseObject(root_obj));
	}

	DBCHECKED(dunstblick_SetView(con, 1));
	DBCHECKED(dunstblick_SetRoot(con, OBJ_ROOT));

	bool running = true;
	while(running)
	{
		DBCHECKED(dunstblick_PumpEvents(con, &events, con));

		usleep(10000);
	}

	dunstblick_Close(con);
	return 0;
}
