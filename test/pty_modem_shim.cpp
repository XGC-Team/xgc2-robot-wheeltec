// PTYs lack modem-control lines. Fixture-only shim accepts those ioctls;
// every serial byte still passes through the actual vendor serial library.
#include <dlfcn.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <unistd.h>
extern "C" int ioctl(int fd, unsigned long request, ...) {
  va_list arguments;
  va_start(arguments, request);
  void *argument = va_arg(arguments, void *);
  va_end(arguments);
  if (isatty(fd) && (request == TIOCMBIS || request == TIOCMBIC)) return 0;
  if (isatty(fd) && request == TIOCMGET) {
    *static_cast<int *>(argument) = 0;
    return 0;
  }
  using Ioctl = int (*)(int, unsigned long, void *);
  static auto original = reinterpret_cast<Ioctl>(dlsym(RTLD_NEXT, "ioctl"));
  return original(fd, request, argument);
}
