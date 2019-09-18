TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

XQLIB += sdl2 sdl2_image sdl2_ttf network io

include($$(XQLIB_ROOT)/xqlib.pri)

SOURCES += \
        api.cpp \
        enums.cpp \
        fontcache.cpp \
        inputstream.cpp \
        layoutparser.cpp \
        layouts.cpp \
        main.cpp \
        object.cpp \
        protocol.cpp \
        rendercontext.cpp \
        resources.cpp \
        types.cpp \
        widget.cpp \
        widget.create.cpp \
        widgets.cpp

HEADERS += \
  api.hpp \
  enums.hpp \
  fontcache.hpp \
  inputstream.hpp \
  layoutparser.hpp \
  layouts.hpp \
  object.hpp \
  protocol.hpp \
  rendercontext.hpp \
  resources.hpp \
  types.hpp \
  types.variant.hpp \
  widget.hpp \
  widgets.hpp

LEXSOURCES += \
  Layout.l

DISTFILES += \
  definitions.lua \
  generator.lua
