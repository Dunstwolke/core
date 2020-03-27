TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

DEFINES += DUNSTBLICK_SERVER

dunstblick_ui_compiler.output  = ${QMAKE_FILE_BASE}.data.h
dunstblick_ui_compiler.commands = $$OUT_PWD/../dunstblick-compiler/dunstblick-compiler ${QMAKE_FILE_NAME} -o ${QMAKE_FILE_OUT} -f header
dunstblick_ui_compiler.input = DUI_FILES
dunstblick_ui_compiler.CONFIG = no_link
QMAKE_EXTRA_COMPILERS += dunstblick_ui_compiler

XQLIB += sdl2 sdl2_image sdl2_ttf network io

include($$(XQLIB_ROOT)/xqlib.pri)

INCLUDEPATH += $$PWD/../libdunstblick

SOURCES += \
        api.cpp \
        enums.cpp \
        fontcache.cpp \
        inputstream.cpp \
        layouts.cpp \
        localsession.cpp \
        main.cpp \
        networksession.cpp \
        object.cpp \
        protocol.cpp \
        rendercontext.cpp \
        resources.cpp \
        session.cpp \
        tcphost.cpp \
        testhost.cpp \
        types.cpp \
        widget.cpp \
        widget.create.cpp \
        widgets.cpp

HEADERS += \
  ../dunstblick-common/data-reader.hpp \
  ../dunstblick-common/data-writer.hpp \
  api.hpp \
  enums.hpp \
  fontcache.hpp \
  inputstream.hpp \
  layoutparser.hpp \
  layouts.hpp \
  localsession.hpp \
  networksession.hpp \
  object.hpp \
  protocol.hpp \
  rectangle_tools.hpp \
  rendercontext.hpp \
  resources.hpp \
  session.hpp \
  tcphost.hpp \
  testhost.hpp \
  types.hpp \
  types.variant.hpp \
  widget.hpp \
  widgets.hpp

DISTFILES += \
  definitions.lua \
  generator.lua

DUI_FILES += \
  discovery-list-item.dui
