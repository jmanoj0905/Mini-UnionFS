# Makefile — Mini-UnionFS
#
# Build with: make
# Clean with: make clean
#
# Requires libfuse3 development headers.
# If fuse3 is installed in a non-standard location, set PKG_CONFIG_PATH:
#   PKG_CONFIG_PATH=/path/to/fuse3/lib/pkgconfig make

CC       = gcc
CFLAGS   = -Wall -Wextra -std=gnu11 $(shell pkg-config --cflags fuse3)
LDFLAGS  = $(shell pkg-config --libs fuse3)

SRCDIR   = src
SRCS     = $(SRCDIR)/main.c $(SRCDIR)/path.c $(SRCDIR)/rw_ops.c $(SRCDIR)/del_ops.c
OBJS     = $(SRCS:.c=.o)
TARGET   = mini_unionfs

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(SRCDIR)/%.o: $(SRCDIR)/%.c $(SRCDIR)/unionfs.h
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET)
