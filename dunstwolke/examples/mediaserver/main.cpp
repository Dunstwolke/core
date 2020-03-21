#include <stdio.h>
#include <stdlib.h>

#include <thread>

#include "bass/bass.h"

// HLS definitions (copied from BASSHLS.H)
#define BASS_SYNC_HLS_SEGMENT	0x10300
#define BASS_TAG_HLS_EXTINF		0x14000

bool OpenURL(char const * url);
bool OpenFile(char const * url);

void DoMeta(HSYNC handle, DWORD channel, DWORD data, void *user);

HSTREAM chan;

int main()
{
    // check the correct BASS was loaded
    if (HIWORD(BASS_GetVersion()) != BASSVERSION) {
        fprintf(stderr, "An incorrect version of BASS was loaded");
        return 1;
    }

    // initialize default output device
    if (!BASS_Init(-1, 44100, 0, nullptr, nullptr)) {
        fprintf(stderr, "Can't initialize device");
        return 1;
    }
    atexit([]() {
        BASS_Free();
    });

    BASS_SetConfig(BASS_CONFIG_NET_PLAYLIST, 1); // enable playlist processing
    BASS_SetConfig(BASS_CONFIG_NET_PREBUF_WAIT, 0); // disable BASS_StreamCreateURL pre-buffering

    BASS_PluginLoad("libbass_aac.so", 0); // load BASS_AAC (if present) for AAC support
    BASS_PluginLoad("libbassflac.so", 0); // load BASSFLAC (if present) for FLAC support
    BASS_PluginLoad("libbasshls.so", 0); // load BASSHLS (if present) for HLS support

    OpenURL("http://sentinel.scenesat.com:8000/scenesatmax");
    // OpenFile("/dunstwolke/music/albums/Morgan Willis/Supernova/Morgan Willis - Supernova - 01 Opening (Vocal Marko Maric).mp3");

    // OpenFile("/dunstwolke/samples/enemy-spotted.mp3");

    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    DoMeta(0, chan, 0, nullptr);

    std::this_thread::sleep_for(std::chrono::seconds(20));

    std::this_thread::sleep_for(std::chrono::seconds(20));

    return 0;
}

// update stream title from metadata
void DoMeta(HSYNC handle, DWORD channel, DWORD data, void *user)
{
    TAG_ID3 const * id3 = reinterpret_cast<TAG_ID3 const *>(BASS_ChannelGetTags(channel, BASS_TAG_ID3));
    if(id3 != nullptr) {
        printf("got id3!\n");
    }

    char const * id3v2 = BASS_ChannelGetTags(channel, BASS_TAG_ID3V2);
    if(id3v2 != nullptr) {
        printf("got id3v2!\n");
    }

    const char *meta = BASS_ChannelGetTags(channel, BASS_TAG_META);
    if (meta) { // got Shoutcast metadata
        printf("Shoutcast: '%s'\n", meta);
    } else {
        meta = BASS_ChannelGetTags(channel, BASS_TAG_OGG);
        if (meta) { // got Icecast/OGG tags
            printf("Icecast/OGG: '%s'\n", meta);
        } else {
            meta = BASS_ChannelGetTags(channel, BASS_TAG_HLS_EXTINF);
            if (meta) { // got HLS segment info
                printf("HLS Segment: '%s'\n", meta);
            }
        }
    }
    fflush(stdout);
}

static void EndSync(HSYNC handle, DWORD channel, DWORD data, void *user)
{
    printf("Stream end\n");
    fflush(stdout);
}

static bool PlayChannel(HSTREAM ch)
{
    BASS_StreamFree(chan); // close old stream

    chan = ch;

    // set syncs for stream title updates
    BASS_ChannelSetSync(chan, BASS_SYNC_META, 0, DoMeta, nullptr);        // Shoutcast
    BASS_ChannelSetSync(chan, BASS_SYNC_OGG_CHANGE, 0, DoMeta, nullptr);  // Icecast/OGG
    BASS_ChannelSetSync(chan, BASS_SYNC_HLS_SEGMENT, 0, DoMeta, nullptr); // HLS
    // set sync for stalling/buffering
    // BASS_ChannelSetSync(chan, BASS_SYNC_STALL, 0, StallSync, 0);
    // set sync for end of stream
    BASS_ChannelSetSync(chan, BASS_SYNC_END, 0, EndSync, nullptr);
    // play it!
    BASS_ChannelPlay(chan, FALSE);

    DoMeta(0, chan, 0, nullptr);

    return true;
}

bool OpenURL(char const * url)
{
    auto const ch = BASS_StreamCreateURL(
                url,
                0,
                BASS_STREAM_BLOCK | BASS_STREAM_STATUS | BASS_STREAM_AUTOFREE,
                nullptr,
                nullptr
                );
    if(ch == 0)
        return false;
    return PlayChannel(ch);
}

bool OpenFile(char const * url)
{
    auto const ch = BASS_StreamCreateFile(
                FALSE,
                url,
                0,
                0,
                0
                );
    if(ch == 0)
        return false;
    return PlayChannel(ch);
}
