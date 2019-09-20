TEMPLATE = subdirs

CONFIG += ordered

SUBDIRS += \
  libdunstblick \
  dunstblick-compiler \
  dunstblick-server \
  examples

HEADERS += \
  dunstblick-common/data-reader.hpp \
  dunstblick-common/data-writer.hpp
