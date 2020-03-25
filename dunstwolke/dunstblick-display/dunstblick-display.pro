TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

DEFINES += DUNSTBLICK_SERVER

XQLIB += sdl2 sdl2_image sdl2_ttf network io

include($$(XQLIB_ROOT)/xqlib.pri)

INCLUDEPATH += $$PWD/../libdunstblick

SOURCES += \
        api.cpp \
        enums.cpp \
        fontcache.cpp \
        inputstream.cpp \
        layouts.cpp \
        main.cpp \
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
