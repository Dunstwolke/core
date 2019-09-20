#include "enums.hpp"
#include "layoutparser.hpp"


#include <iostream>
#include <fstream>
#include <getopt.h>

#include <xio/simple>

#include <nlohmann/json.hpp>

int main(int argc, char * const * argv)
{
	char const * srcFile = nullptr;
	char const * dstFile = nullptr;
	char const * cfgFile = nullptr;

	int c, opterr = 0;
	while ((c = getopt (argc, argv, "o:c:")) != -1)
	{
		switch (c)
		{
			case 'o':
				dstFile = optarg;
				break;

			case 'c':
				cfgFile = optarg;
				break;

			case '?':
				if (optopt == 'c')
					fprintf (stderr, "Option -%c requires an argument.\n", optopt);
				else if (isprint (optopt))
					fprintf (stderr, "Unknown option `-%c'.\n", optopt);
				else
					fprintf (stderr,
					         "Unknown option character `\\x%x'.\n",
					         optopt);
				return 1;
			default:
				abort ();
		}
	}

	if(optind == argc) {
		printf("Missing input file!\n");
		return 1;
	}
	srcFile = argv[optind];

	if(dstFile == nullptr) {
		printf("Missing output file!\n");
		return 1;
	}

	LayoutParser layout_parser;

	if(cfgFile != nullptr)
	{
		auto const file = xio::load_raw(cfgFile);

		auto const json = nlohmann::json::parse(file.begin(), file.end());

		if(auto props = json.find("properties"); props != json.end())
		{
			for(auto it = props.value().begin(); it != props.value().end(); it++)
			{
				layout_parser.knownProperties.emplace(it.key(), PropertyName(it.value().get<int>()));
			}
		}

		if(auto props = json.find("resources"); props != json.end())
		{
			for(auto it = props.value().begin(); it != props.value().end(); it++)
			{
				layout_parser.knownResources.emplace(it.key(), PropertyName(it.value().get<int>()));
			}
		}

//		if(auto props = json.find("properties"); props != json.end())
//		{
//			for(auto it = props.value().begin(); it != props.value().end(); it++)
//			{
//				layout_parser.knownProperties.emplace(it.key(), PropertyName(it.value().get<int>()));
//			}
//		}
	}

	std::ifstream input_src(srcFile);

	std::stringstream formDataBuffer;
	layout_parser.compile(input_src, formDataBuffer);

	auto formData = formDataBuffer.str();

	std::ofstream output_file(dstFile);
	output_file.write(formData.data(), formData.size());

	return 0;
}
