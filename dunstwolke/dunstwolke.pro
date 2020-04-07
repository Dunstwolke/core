TEMPLATE = subdirs

CONFIG += ordered

SUBDIRS += \
  dunstblick-display

DISTFILES += ../.clang-format\
  dunstblick-common/definitions.lua

HEADERS += \
  dunstblick-common/dunst-encoding.h
