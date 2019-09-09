TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

XQLIB += sdl2 sdl2_ttf network io

include($$(XQLIB_ROOT)/xqlib.pri)

SOURCES += \
        fontcache.cpp \
        inputstream.cpp \
        layouts.cpp \
        main.cpp \
        rendercontext.cpp \
        types.cpp \
        widget.cpp \
        widgets.cpp

HEADERS += \
  enums.hpp \
  fontcache.hpp \
  inputstream.hpp \
  layouts.hpp \
  rendercontext.hpp \
  types.hpp \
  widget.hpp \
  widgets.hpp
