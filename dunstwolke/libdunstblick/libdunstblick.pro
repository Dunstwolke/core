TEMPLATE = lib
CONFIG += console
CONFIG -= app_bundle
CONFIG -= qt
CONFIG += static

XQLIB += network io
include($$(XQLIB_ROOT)/xqlib.pri)

DEFINES += DUNSTBLICK_LIBRARY

INCLUDEPATH += ../ext/picohash
INCLUDEPATH += ../ext/concurrentqueue

SOURCES += \
  dunstblick.cpp \
  picohash.c

HEADERS += \
  dunstblick-internal.hpp \
  dunstblick.h
