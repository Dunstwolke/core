TEMPLATE = subdirs

CONFIG += ordered

SUBDIRS += \
  libdunstblick \
  dunstblick-compiler \
  dunstblick-display \
  examples

DISTFILES += ../.clang-format
