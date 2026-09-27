PROTO = wlr-virtual-pointer-unstable-v1
CFLAGS ?= -O2 -Wall -Wno-unused-parameter

sidecar-pointer: sidecar-pointer.c $(PROTO)-client-protocol.h $(PROTO)-protocol.c
	$(CC) $(CFLAGS) -o $@ sidecar-pointer.c $(PROTO)-protocol.c $$(pkg-config --cflags --libs wayland-client)

$(PROTO)-client-protocol.h: $(PROTO).xml
	wayland-scanner client-header $< $@

$(PROTO)-protocol.c: $(PROTO).xml
	wayland-scanner private-code $< $@

clean:
	rm -f sidecar-pointer $(PROTO)-client-protocol.h $(PROTO)-protocol.c
