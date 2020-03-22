TEMPLATE = lib
CONFIG += console
CONFIG -= app_bundle
CONFIG -= qt
CONFIG += static

XQLIB += network io
include($$(XQLIB_ROOT)/xqlib.pri)

DEFINES += DUNSTBLICK_LIBRARY

SOURCES += \
  dunstblick.cpp

HEADERS += \
  dunstblick-internal.hpp \
  dunstblick.h
