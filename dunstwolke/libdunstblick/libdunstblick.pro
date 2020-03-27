TEMPLATE = lib
CONFIG += console
CONFIG -= app_bundle
CONFIG -= qt
CONFIG += static

XQLIB += network io
include($$(XQLIB_ROOT)/xqlib.pri)

DEFINES += DUNSTBLICK_LIBRARY

SYSTEM_INCLUDEPATH += -isystem $$PWD/../ext/picohash -isystem $$PWD/../ext/concurrentqueue

QMAKE_CFLAGS += $$SYSTEM_INCLUDEPATH
QMAKE_CXXFLAGS += $$SYSTEM_INCLUDEPATH

SOURCES += \
  dunstblick.cpp \
  picohash.c

HEADERS += \
  dunstblick-internal.hpp \
  dunstblick.h
