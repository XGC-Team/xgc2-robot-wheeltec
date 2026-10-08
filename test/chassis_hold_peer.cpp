// Test peer: uses the installed SDK for discovery, fencing and transport.
#include <xgc2/xrpc/http.hpp>
#include <json/json.h>
#include <chrono>
#include <iostream>
#include <memory>
#include <stdexcept>

int main(int argc, char **argv) {
  try {
    if (argc != 3 && argc != 6) throw std::invalid_argument("socket GET | socket POST revision robot held");
    using namespace xgc2::xrpc;
    HttpClient discovery(argv[1]);
    HttpRequest describe;
    describe.method = "GET";
    describe.target = "/v1/chassis/descriptor";
    auto response = discovery.call(describe, Clock::now()+std::chrono::seconds(1));
    Json::CharReaderBuilder reader;
    const std::unique_ptr<Json::CharReader> parser(reader.newCharReader());
    Json::Value descriptor;
    std::string errors;
    if (response.status != 200 || !parser->parse(response.body.data(),
        response.body.data()+response.body.size(), &descriptor, &errors))
      throw std::runtime_error("ServiceRef discovery failed");
    HttpClient client(argv[1], {}, descriptor["instance_id"].asString());
    HttpRequest call;
    call.target = "/v1/chassis/hold";
    call.method = argv[2];
    if (argc == 6) {
      Json::Value body;
      body["expected_revision"] = Json::UInt64(std::stoull(argv[3]));
      Json::Value change;
      change["robot_id"] = argv[4];
      const std::string held(argv[5]);
      if (held != "true" && held != "false") throw std::invalid_argument("held must be true or false");
      change["held"] = held == "true";
      body["changes"].append(change);
      Json::StreamWriterBuilder writer;
      writer["indentation"] = "";
      call.body = Json::writeString(writer, body);
      call.headers.emplace_back("Content-Type", "application/json");
    }
    response = client.call(call, Clock::now()+std::chrono::milliseconds(240));
    std::cout << response.status << '\n' << response.body << '\n';
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
