TEMPLATE = lib
CONFIG += console
CONFIG -= app_bundle
CONFIG -= qt

XQLIB += network io
include($$(XQLIB_ROOT)/xqlib.pri)

DEFINES += DUNSTBLICK_LIBRARY

SOURCES += \
  dunstblick.cpp

HEADERS += \
  dunstblick.h
