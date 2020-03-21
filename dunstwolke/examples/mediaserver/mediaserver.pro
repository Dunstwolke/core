TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

#QMAKE_CFLAGS   += -O3
#QMAKE_CXXFLAGS += -O3
#QMAKE_LFLAGS   += -O3

QMAKE_LIBS += -L$$quote($$PWD/bass/x86_64) -lbass

SOURCES += \
        main.cpp

DISTFILES += \
  README.md

HEADERS += \
  bass/bass.h
