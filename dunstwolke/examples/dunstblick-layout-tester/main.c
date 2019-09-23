#include <stdio.h>
#include <stdlib.h>
#include <dunstblick.h>

#define DBCHECKED(_X) do { \
		dunstblick_Error err = _X; \
		if(err != DUNSTBLICK_ERROR_NONE) \
		{ \
			printf("failed to execute " #_X ": %d\n", err); \
			return 1; \
		} \
	} while(0)

int main(int argc, char ** argv)
{
	if((argc <= 1) || (argc > 3))
	{
		fprintf(stderr,
			"usage: dunstblick-layout-tester [layout file] [server] [port]\n"
			"[layout file] is required and a pre-compiled layout\n"
		    "[server]      is the ui server hostname and optional (defaults to 127.0.0.1)\n"
		    "[port]        is the ui server port and option (defaults to 1309)\n");
		return 1;
	}

	char const * fileName = argv[1];
	char const * server = (argc > 2) ? argv[2] : "127.0.0.1";
	int portNum = (argc > 3) ? strtod(argv[3], NULL) : 1309;

	FILE * f = fopen(fileName, "rb");
	if(f == NULL) {
		fprintf(stderr, "root file not found!\n");
		return 1;
	}

	fseek(f, 0, SEEK_END);
	size_t len = ftell(f);
	fseek(f, 0, SEEK_SET);

	void * buffer = malloc(len);

	size_t offset = 0;
	while(offset < len)
	{
		size_t delta = fread((char*)buffer + offset, 1, len - offset, f);
		if(delta == 0) {
			fclose(f);
			fprintf(stderr, "failed to read root file!\n");
			return 1;
		}
		offset += delta;
	}

	fclose(f);

	dunstblick_Connection * con = dunstblick_Open(server, portNum);
	if(con == NULL) {
		printf("Failed to establish connection!\n");
		return 1;
	}

	DBCHECKED(dunstblick_UploadResource(con, 1, DUNSTBLICK_RESOURCE_LAYOUT, buffer, len));

	DBCHECKED(dunstblick_SetView(con, 1));

	dunstblick_Close(con);

	return 0;
}
