TEMPLATE = subdirs

CONFIG += ordered

SUBDIRS += \
  dunstblick-compiler \
  dunstblick-display

DISTFILES += ../.clang-format\
  dunstblick-common/definitions.lua

HEADERS += \
  dunstblick-common/dunst-encoding.h
