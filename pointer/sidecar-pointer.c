// sidecar-pointer: a wlr virtual pointer bound to one output, driven by
// line commands on stdin. omarchy-sidecar uses it to turn iPad touches into
// pointer input on the headless output that the iPad is showing.
//
//   usage: sidecar-pointer <output-name>
//
//   m X Y      absolute move, X/Y normalized 0..1 within the output
//   d / u      left button down / up
//   rd / ru    right button down / up
//   s DX DY    scroll by DX/DY (wayland axis units, positive = down/right)
//   S          end of a scroll gesture (axis_stop)
//   q          quit
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define EXTENT 65535u

struct out {
  struct wl_output *wl;
  char *name;
  struct out *next;
};

static struct zwlr_virtual_pointer_manager_v1 *manager;
static uint32_t manager_version;
static struct out *outputs;

static void out_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph,
                         int32_t sub, const char *make, const char *model, int32_t t) {}
static void out_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) {}
static void out_done(void *d, struct wl_output *o) {}
static void out_scale(void *d, struct wl_output *o, int32_t s) {}
static void out_name(void *d, struct wl_output *o, const char *name) {
  struct out *e = d;
  free(e->name);
  e->name = strdup(name);
}
static void out_description(void *d, struct wl_output *o, const char *desc) {}

static const struct wl_output_listener out_listener = {
  .geometry = out_geometry,
  .mode = out_mode,
  .done = out_done,
  .scale = out_scale,
  .name = out_name,
  .description = out_description,
};

static void reg_global(void *d, struct wl_registry *reg, uint32_t id, const char *iface, uint32_t ver) {
  if (strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
    manager_version = ver < 2 ? ver : 2;
    manager = wl_registry_bind(reg, id, &zwlr_virtual_pointer_manager_v1_interface, manager_version);
  } else if (strcmp(iface, wl_output_interface.name) == 0 && ver >= 4) {
    struct out *e = calloc(1, sizeof *e);
    e->wl = wl_registry_bind(reg, id, &wl_output_interface, 4);
    wl_output_add_listener(e->wl, &out_listener, e);
    e->next = outputs;
    outputs = e;
  }
}
static void reg_remove(void *d, struct wl_registry *reg, uint32_t id) {}
static const struct wl_registry_listener reg_listener = { reg_global, reg_remove };

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static uint32_t clamp_norm(double v) {
  if (v < 0) v = 0;
  if (v > 1) v = 1;
  return (uint32_t)(v * EXTENT + 0.5);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <output-name>\n", argv[0]);
    return 2;
  }
  struct wl_display *dpy = wl_display_connect(NULL);
  if (!dpy) { fprintf(stderr, "sidecar-pointer: no wayland display\n"); return 1; }
  struct wl_registry *reg = wl_display_get_registry(dpy);
  wl_registry_add_listener(reg, &reg_listener, NULL);
  wl_display_roundtrip(dpy);
  wl_display_roundtrip(dpy);  // collect wl_output names

  if (!manager) { fprintf(stderr, "sidecar-pointer: compositor lacks zwlr_virtual_pointer_manager_v1\n"); return 1; }

  struct wl_output *target = NULL;
  for (struct out *e = outputs; e; e = e->next)
    if (e->name && strcmp(e->name, argv[1]) == 0) target = e->wl;
  if (!target) { fprintf(stderr, "sidecar-pointer: output %s not found\n", argv[1]); return 1; }
  if (manager_version < 2) { fprintf(stderr, "sidecar-pointer: manager v%u cannot bind to an output\n", manager_version); return 1; }

  struct zwlr_virtual_pointer_v1 *ptr =
    zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(manager, NULL, target);
  wl_display_flush(dpy);
  printf("ready\n");
  fflush(stdout);

  char *line = NULL;
  size_t cap = 0;
  while (getline(&line, &cap, stdin) > 0) {
    double a = 0, b = 0;
    uint32_t t = now_ms();
    switch (line[0]) {
      case 'm':
        if (sscanf(line + 1, "%lf %lf", &a, &b) == 2) {
          zwlr_virtual_pointer_v1_motion_absolute(ptr, t, clamp_norm(a), clamp_norm(b), EXTENT, EXTENT);
          zwlr_virtual_pointer_v1_frame(ptr);
        }
        break;
      case 'd':
      case 'u':
        zwlr_virtual_pointer_v1_button(ptr, t, BTN_LEFT,
          line[0] == 'd' ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
        zwlr_virtual_pointer_v1_frame(ptr);
        break;
      case 'r':
        zwlr_virtual_pointer_v1_button(ptr, t, BTN_RIGHT,
          line[1] == 'd' ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
        zwlr_virtual_pointer_v1_frame(ptr);
        break;
      case 's':
        if (sscanf(line + 1, "%lf %lf", &a, &b) == 2) {
          zwlr_virtual_pointer_v1_axis_source(ptr, WL_POINTER_AXIS_SOURCE_FINGER);
          if (b != 0) zwlr_virtual_pointer_v1_axis(ptr, t, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(b));
          if (a != 0) zwlr_virtual_pointer_v1_axis(ptr, t, WL_POINTER_AXIS_HORIZONTAL_SCROLL, wl_fixed_from_double(a));
          zwlr_virtual_pointer_v1_frame(ptr);
        }
        break;
      case 'S':
        zwlr_virtual_pointer_v1_axis_source(ptr, WL_POINTER_AXIS_SOURCE_FINGER);
        zwlr_virtual_pointer_v1_axis_stop(ptr, t, WL_POINTER_AXIS_VERTICAL_SCROLL);
        zwlr_virtual_pointer_v1_axis_stop(ptr, t, WL_POINTER_AXIS_HORIZONTAL_SCROLL);
        zwlr_virtual_pointer_v1_frame(ptr);
        break;
      case 'q':
        goto done;
    }
    if (wl_display_flush(dpy) < 0) break;
  }
done:
  zwlr_virtual_pointer_v1_destroy(ptr);
  wl_display_flush(dpy);
  wl_display_disconnect(dpy);
  return 0;
}
