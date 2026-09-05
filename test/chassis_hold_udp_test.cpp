#include "xgc_chassis_hold/udp.hpp"

#include <poll.h>

#include <atomic>
#include <chrono>
#include <future>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

class Client {
 public:
  Client() : fd_(socket(AF_INET, SOCK_DGRAM, 0)) {
    require(fd_ >= 0, "client socket failed");
    std::memset(&to_, 0, sizeof(to_));
    to_.sin_family = AF_INET;
    to_.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    to_.sin_port = htons(static_cast<uint16_t>(xgc_chassis_hold::kPort));
  }
  ~Client() { close(fd_); }
  void send(const std::vector<unsigned char> &frame) {
    require(sendto(fd_, frame.data(), frame.size(), 0,
                   reinterpret_cast<const sockaddr *>(&to_), sizeof(to_)) ==
                static_cast<ssize_t>(frame.size()), "send failed");
  }
  std::vector<unsigned char> receive(int timeout_ms = 2000) {
    pollfd item = {fd_, POLLIN, 0};
    int ready;
    do {
      ready = poll(&item, 1, timeout_ms);
    } while (ready < 0 && errno == EINTR);
    require(ready >= 0, "poll failed");
    if (ready == 0) {
      return {};
    }
    unsigned char bytes[32];
    const ssize_t count = recv(fd_, bytes, sizeof(bytes), 0);
    require(count >= 0, "receive failed");
    return std::vector<unsigned char>(bytes, bytes + count);
  }
 private:
  int fd_;
  sockaddr_in to_;
};

struct Registration {
  explicit Registration(xgc_chassis_hold::Gate &value) : gate(value) {
    xgc_chassis_hold::Hub::instance().add(&gate);
  }
  ~Registration() { xgc_chassis_hold::Hub::instance().remove(&gate); }
  xgc_chassis_hold::Gate &gate;
};

std::vector<unsigned char> request(bool held, unsigned id,
                                   const std::string &robot = "test") {
  std::vector<unsigned char> frame(xgc_chassis_hold::kRequestBytes, 0);
  xgc_chassis_hold::writeU32LE(frame.data(), xgc_chassis_hold::kMagic);
  frame[4] = xgc_chassis_hold::kVersion;
  frame[5] = held ? 1 : 0;
  xgc_chassis_hold::writeU32LE(frame.data() + 8, id);
  require(robot.size() <= xgc_chassis_hold::kRobotIdBytes, "robot id too long");
  std::memcpy(frame.data() + 12, robot.data(), robot.size());
  return frame;
}

void expectAck(Client &client, unsigned id, unsigned status, bool held) {
  const auto ack = client.receive();
  require(ack.size() == xgc_chassis_hold::kAckBytes, "missing exact-size ACK");
  require(xgc_chassis_hold::readU32LE(ack.data()) == xgc_chassis_hold::kMagic,
          "bad ACK magic");
  require(ack[4] == xgc_chassis_hold::kVersion, "bad ACK version");
  require(ack[5] == (held ? 1 : 0) && ack[6] == status, "bad ACK state/status");
  require(xgc_chassis_hold::readU32LE(ack.data() + 8) == id, "bad ACK request id");
}

void countZero(void *context) {
  static_cast<std::atomic<int> *>(context)->fetch_add(1);
}

void frameTest() {
  std::atomic<int> zero_count{0};
  xgc_chassis_hold::Gate gate("test");
  gate.setZeroThunk(&countZero, &zero_count);
  Registration registration(gate);
  Client client;
  client.send(request(true, 1));
  expectAck(client, 1, 0, true);
  require(gate.held() && zero_count.load() == 1, "valid hold failed");
  client.send(request(true, 2));
  expectAck(client, 2, 0, true);
  require(zero_count.load() == 1, "duplicate hold fired zero twice");

  auto oversized_release = request(false, 3);
  oversized_release.push_back(0);
  client.send(oversized_release);
  const bool no_oversized_ack = client.receive(150).empty();
  require(no_oversized_ack && gate.held(), "oversized datagram released held gate");

  auto large_release = request(false, 4);
  large_release.resize(4096, 0);
  client.send(large_release);
  require(client.receive(150).empty() && gate.held(), "large datagram accepted");
  auto short_release = request(false, 5);
  short_release.pop_back();
  client.send(short_release);
  require(client.receive(150).empty() && gate.held(), "short datagram accepted");
  auto bad_magic = request(false, 6);
  bad_magic[0] = 0;
  client.send(bad_magic);
  require(client.receive(150).empty() && gate.held(), "bad magic accepted");
  auto bad_version = request(false, 7);
  bad_version[4] = 99;
  client.send(bad_version);
  require(client.receive(150).empty() && gate.held(), "bad version accepted");
  client.send(request(false, 8, "unknown"));
  expectAck(client, 8, 1, false);
  require(gate.held(), "unknown id affected exact gate");
  client.send(request(false, 9));
  expectAck(client, 9, 0, false);
  require(!gate.held(), "valid release failed");

  std::atomic<int> fallback_count{0};
  xgc_chassis_hold::Gate fallback("");
  fallback.setZeroThunk(&countZero, &fallback_count);
  Registration fallback_registration(fallback);
  client.send(request(true, 10));
  expectAck(client, 10, 0, true);
  require(gate.held() && !fallback.held(), "exact match did not take precedence");
  client.send(request(true, 11, "other"));
  expectAck(client, 11, 0, true);
  require(fallback.held() && fallback_count.load() == 1, "wildcard regression");
}

struct BlockingZero {
  std::promise<void> entered;
  std::shared_future<void> release;
  static void run(void *context) {
    BlockingZero &self = *static_cast<BlockingZero *>(context);
    self.entered.set_value();
    self.release.wait();
  }
};

void removalTest() {
  std::promise<void> release;
  BlockingZero callback;
  callback.release = release.get_future().share();
  auto entered = callback.entered.get_future();
  xgc_chassis_hold::Gate gate("test");
  gate.setZeroThunk(&BlockingZero::run, &callback);
  Registration registration(gate);
  Client client;
  client.send(request(true, 20));
  if (entered.wait_for(std::chrono::seconds(2)) != std::future_status::ready) {
    release.set_value();
    throw std::runtime_error("zero callback did not start");
  }
  std::promise<void> removing;
  auto attempting = removing.get_future();
  auto removed = std::async(std::launch::async, [&gate, &removing] {
    removing.set_value();
    xgc_chassis_hold::Hub::instance().remove(&gate);
  });
  attempting.wait();
  const bool returned_early =
      removed.wait_for(std::chrono::milliseconds(150)) == std::future_status::ready;
  // Always release and join, including the baseline failure path.
  release.set_value();
  removed.get();
  expectAck(client, 20, 0, true);
  client.send(request(false, 21));
  expectAck(client, 21, 1, false);
  require(!returned_early, "remove returned while zero callback was still using its owner");
}

}  // namespace

int main(int argc, char **argv) {
  try {
    require(argc == 2, "usage: udp_regression_test frames|remove");
    const std::string test = argv[1];
    if (test == "frames") {
      frameTest();
    } else if (test == "remove") {
      removalTest();
    } else {
      throw std::runtime_error("unknown test");
    }
    std::cout << "PASS " << test << '\n';
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
