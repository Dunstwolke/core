TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

XQLIB += sdl2 network io

include($$(XQLIB_ROOT)/xqlib.pri)

SOURCES += \
        inputstream.cpp \
        layouts.cpp \
        main.cpp \
        widget.cpp

HEADERS += \
  enums.hpp \
  inputstream.hpp \
  layouts.hpp \
  types.hpp \
  widget.hpp
