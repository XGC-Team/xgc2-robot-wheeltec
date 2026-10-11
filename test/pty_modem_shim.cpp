// PTYs lack modem-control lines. Fixture-only shim accepts those ioctls;
// every serial byte still passes through the actual vendor serial library.
#include <dlfcn.h>
#include <cstdlib>
#include <fcntl.h>
#include <stdarg.h>
#include <string>
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

// Pause a native command callback after ROS copied its callback queue. The
// next command can then be received before release and dispatched after it.
extern "C" ssize_t write(int fd, const void *data, size_t size) {
  const char *barrier = std::getenv("WHEELTEC_TEST_WRITE_BARRIER");
  const auto *bytes = static_cast<const unsigned char *>(data);
  if (barrier && size == 11 && bytes[0] == 0x7b && bytes[10] == 0x7d && isatty(fd) && access(barrier, F_OK) == 0) {
    const std::string blocked = std::string(barrier) + ".blocked";
    const int marker = open(blocked.c_str(), O_CREAT | O_WRONLY, 0600);
    if (marker >= 0) close(marker);
    while (access(barrier, F_OK) == 0) usleep(1000);
  }
  using Write = ssize_t (*)(int, const void *, size_t);
  static auto original = reinterpret_cast<Write>(dlsym(RTLD_NEXT, "write"));
  return original(fd, data, size);
}
