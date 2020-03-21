TEMPLATE = app
CONFIG += console c++11
CONFIG -= app_bundle
CONFIG -= qt

XQLIB += json io

include($$(XQLIB_ROOT)/xqlib.pri)

DEFINES += DUNSTBLICK_COMPILER

INCLUDEPATH += $$PWD/../dunstblick-display

SOURCES += \
        layoutparser.cpp \
        main.cpp \
        $$PWD/../dunstblick-display/enums.cpp \
        $$PWD/../dunstblick-display/types.cpp

HEADERS += \
  layoutparser.hpp

LEXSOURCES += \
  Layout.l
