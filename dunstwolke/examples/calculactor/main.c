#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

enum MathCommand { COPY=0, ADD, SUBTRACT, MULTIPLY, DIVIDE };

static float current_value = 0.0f;
static char current_input[64] = "";
static bool shows_result = false;
static enum MathCommand next_command = COPY;

static void refresh_screen(dunstblick_Connection * con)
{
	dunstblick_Value result = {
	    .type = DUNSTBLICK_TYPE_STRING,
	    .string = current_input,
	};

	dunstblick_Error error = dunstblick_SetProperty(con, OBJ_ROOT, PROP_RESULT, &result);
	if(error != DUNSTBLICK_ERROR_NONE)
		printf("failed to refresh screen: %d\n", error);
}

static void enter_char(char c)
{
	if(shows_result)
		strcpy(current_input, "");

	char buf[2] = { c ,0 };
	strcat(current_input, buf);
	shows_result = false;
}

static void execute_command()
{
	float val = strtof(current_input, NULL);
	switch(next_command)
	{
		case COPY:
			current_value = val;
			break;
		case ADD:
			current_value += val;
			break;
		case SUBTRACT:
			current_value -= val;
			break;
		case MULTIPLY:
			current_value *= val;
			break;
		case DIVIDE:
			current_value /= val;
			break;
	}
	shows_result = true;
}

static void onCallback(dunstblick_CallbackID cid, void * context)
{
	switch(cid)
	{
		case 1:
		case 2:
		case 3:
		case 4:
		case 5:
		case 6:
		case 7:
		case 8:
		case 9:
		case 10:
		{
			int number = cid % 10;
			enter_char((char)('0' + number));
			break;
		}

		case 11: // "+"
			execute_command();
			next_command = ADD;
			break;

		case 12: // "-"
			execute_command();
			next_command = SUBTRACT;
			break;

		case 13: // "*"
			execute_command();
			next_command = MULTIPLY;
			break;

		case 14: // "/"
			execute_command();
			next_command = DIVIDE;
			break;

		case 15: // "C"
			strcpy(current_input, "0");
			current_value = 0.0f;
			shows_result = false;
			next_command = COPY;
			break;

		case 16: // "CE"
			strcpy(current_input, "");
			shows_result = false;
			break;

		case 17: // ','
		{
			if(strchr(current_input, '.') == NULL)
				enter_char('.');
			break;
		}

		case 18: // "="
		{
			execute_command();
			next_command = COPY;
			break;
		}

		default:
			printf("got handled callback: %d\n", cid);
			fflush(stdout);
			break;
	}

	if(shows_result)
		sprintf(current_input, "%f", (double)current_value);

	refresh_screen(context);
}

static void onPropertyChanged(dunstblick_ObjectID oid, dunstblick_PropertyName property, dunstblick_Value const * value)
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
