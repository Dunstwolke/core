#include "enums.hpp"
#include "layoutparser.hpp"

#include <filesystem>
#include <fstream>
#include <getopt.h>
#include <iostream>

#include <xio/simple>

#include <nlohmann/json.hpp>

int main(int argc, char * const * argv)
{
    char const * srcFile = nullptr;
    char const * dstFile = nullptr;
    char const * cfgFile = nullptr;

    enum OutputFormat
    {
        FMT_BINARY = 0,
        FMT_HEADER = 1,
    } format = FMT_BINARY;

    int c = 0;
    while ((c = getopt(argc, argv, "f:o:c:")) != -1) {
        switch (c) {
            case 'o':
                dstFile = optarg;
                break;

            case 'c':
                cfgFile = optarg;
                break;

            case 'f':
                if (strcmp(optarg, "binary") == 0) {
                    format = FMT_BINARY;
                } else if (strcmp(optarg, "header") == 0) {
                    format = FMT_HEADER;
                } else {
                    fprintf(stderr, "Unknown outformat format %s.\n", optarg);
                    return 1;
                }
                break;

            case '?':
                if (optopt == 'c')
                    fprintf(stderr, "Option -%c requires an argument.\n", optopt);
                else if (isprint(optopt))
                    fprintf(stderr, "Unknown option `-%c'.\n", optopt);
                else
                    fprintf(stderr, "Unknown option character `\\x%x'.\n", optopt);
                return 1;
            default:
                abort();
        }
    }

    if (optind == argc) {
        printf("Missing input file!\n");
        return 1;
    }
    srcFile = argv[optind];

    if (dstFile == nullptr) {
        printf("Missing output file!\n");
        return 1;
    }

    LayoutParser layout_parser;

    if (cfgFile != nullptr) {
        auto const file = xio::load_raw(cfgFile);

        auto const json = nlohmann::json::parse(file.begin(), file.end());

        if (auto props = json.find("properties"); props != json.end()) {
            for (auto it = props.value().begin(); it != props.value().end(); it++) {
                layout_parser.knownProperties.emplace(it.key(), PropertyName(it.value().get<unsigned int>()));
            }
        }

        if (auto props = json.find("resources"); props != json.end()) {
            for (auto it = props.value().begin(); it != props.value().end(); it++) {
                layout_parser.knownResources.emplace(it.key(), UIResourceID(it.value().get<unsigned int>()));
            }
        }

        if (auto props = json.find("callbacks"); props != json.end()) {
            for (auto it = props.value().begin(); it != props.value().end(); it++) {
                layout_parser.knownCallbacks.emplace(it.key(), EventID(it.value().get<unsigned int>()));
            }
        }
    }

    std::ifstream input_src(srcFile);

    std::stringstream formDataBuffer;

    if (not layout_parser.compile(input_src, formDataBuffer)) {
        return 1;
    }

    switch (format) {
        case FMT_BINARY: {
            std::ofstream output_file(dstFile);
            output_file << formDataBuffer.rdbuf();
            break;
        }
        case FMT_HEADER: {
            std::ofstream output_file(dstFile);
            auto const bytes = formDataBuffer.str();
            for (size_t i = 0; i < bytes.size(); i++) {
                uint8_t byte = uint8_t(bytes.at(i));

                if (i > 0 and (i % 16) == 0)
                    output_file << std::endl;
                output_file << "0x" << std::hex << std::setw(2) << std::setfill('0') << size_t(byte) << ", ";
            }
            output_file << std::endl;
            break;
        }
        default:
            assert(false and "not implemented yet");
    }

    return 0;
}
