TEMPLATE = subdirs

CONFIG += ordered

SUBDIRS += \
  libdunstblick \
  dunstblick-compiler \
  dunstblick-display \
  examples

DISTFILES += ../.clang-format\
  dunstblick-common/definitions.lua

HEADERS += \
  dunstblick-common/dunst-encoding.h
