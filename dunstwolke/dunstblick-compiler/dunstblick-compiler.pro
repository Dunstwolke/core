TEMPLATE = app
CONFIG += console c++11
CONFIG -= app_bundle
CONFIG -= qt

XQLIB += json io

include($$(XQLIB_ROOT)/xqlib.pri)

DEFINES += DUNSTBLICK_COMPILER

INCLUDEPATH += $$PWD/../dunstblick-server

SOURCES += \
        layoutparser.cpp \
        main.cpp \
        $$PWD/../dunstblick-server/enums.cpp \
        $$PWD/../dunstblick-server/types.cpp

HEADERS += \
  layoutparser.hpp

LEXSOURCES += \
  Layout.l
