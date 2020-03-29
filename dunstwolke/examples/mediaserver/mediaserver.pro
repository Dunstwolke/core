TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

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

QMAKE_LIBS += -L$$quote($$PWD/bass/x86_64) -lbass

dunstblick_ui_compiler.output  = ${QMAKE_FILE_BASE}.data.h
dunstblick_ui_compiler.commands = $$OUT_PWD/../../dunstblick-compiler/dunstblick-compiler ${QMAKE_FILE_NAME} -o ${QMAKE_FILE_OUT} -f header -c $$PWD/layouts/server.json
dunstblick_ui_compiler.input = DUI_FILES
dunstblick_ui_compiler.CONFIG = no_link
QMAKE_EXTRA_COMPILERS += dunstblick_ui_compiler

SOURCES += \
        main.cpp

DUI_FILES += \
  layouts/develop.dui \
  layouts/main.dui \
  layouts/menu.dui \
  layouts/searchitem.dui \
  layouts/searchlist.dui

DISTFILES += \
  README.md \
  layouts/server.json

HEADERS += \
  bass/bass.h
