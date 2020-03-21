#include <iostream>
#include <xio/simple>
#include <nlohmann/json.hpp>

#include "dunstblick.h"

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
			"usage: dunstblick-layout-tester [resource json] [server] [port]\n"
			"[resource json] required, json-file defining all resources\n"
		    "[server]      is the ui server hostname and optional (defaults to 127.0.0.1)\n"
		    "[port]        is the ui server port and option (defaults to 1309)\n");
		return 1;
	}

	char const * fileName = argv[1];
	char const * server = (argc > 2) ? argv[2] : "127.0.0.1";
	int portNum = (argc > 3) ? strtod(argv[3], NULL) : 1309;

    auto json_blob = xio::load_raw(fileName);
    auto const json = nlohmann::json::parse(json_blob.begin(), json_blob.end());

	dunstblick_Connection * con = dunstblick_Open(server, portNum);
	if(con == nullptr) {
		printf("Failed to establish connection!\n");
		return 1;
	}

    for(auto const & resource : json)
    {
        auto const id = resource.value("id", 0U);
        auto const type = resource.value("type", std::string("bitmap"));
        auto const file = resource.value("file", std::string(""));

        dunstblick_ResourceKind kind = DUNSTBLICK_RESOURCE_BITMAP;
        if(type == "drawing")
            kind = DUNSTBLICK_RESOURCE_DRAWING;
        else if(type == "layout")
            kind = DUNSTBLICK_RESOURCE_LAYOUT;

        auto const blob = xio::load_raw(file);

        DBCHECKED(dunstblick_UploadResource(con, id, kind, blob.data(), blob.size()));
    }
	dunstblick_Close(con);

	return 0;
}
