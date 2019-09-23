TEMPLATE = app
CONFIG += console
CONFIG -= app_bundle
CONFIG -= qt

SOURCES += \
        main.c

LIBS += -lpthread

win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../../libdunstblick/release/ -llibdunstblick
else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../../libdunstblick/debug/ -llibdunstblick
else:unix: LIBS += -L$$OUT_PWD/../../libdunstblick/ -llibdunstblick

INCLUDEPATH += $$PWD/../../libdunstblick
DEPENDPATH += $$PWD/../../libdunstblick

# static linking
win32-g++:CONFIG(release, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../../libdunstblick/release/liblibdunstblick.a
else:win32-g++:CONFIG(debug, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../../libdunstblick/debug/liblibdunstblick.a
else:win32:!win32-g++:CONFIG(release, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../../libdunstblick/release/libdunstblick.lib
else:win32:!win32-g++:CONFIG(debug, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../../libdunstblick/debug/libdunstblick.lib
else:unix: PRE_TARGETDEPS += $$OUT_PWD/../../libdunstblick/liblibdunstblick.a
