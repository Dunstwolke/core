TEMPLATE = lib
CONFIG += console c++11
CONFIG -= app_bundle
CONFIG -= qt
CONFIG += static

XQLIB += network io
include($$(XQLIB_ROOT)/xqlib.pri)

SOURCES += \
  dunstblick.cpp

HEADERS += \
  dunstblick.h
