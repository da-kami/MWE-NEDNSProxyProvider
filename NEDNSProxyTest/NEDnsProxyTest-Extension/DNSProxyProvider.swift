//
//  DNSProxyProvider.swift
//  NEDnsProxyTest-Extension
//
//  Created by Daniel Karzel on 3/9/2025.
//

import NetworkExtension
import OSLog

class DNSProxyProvider: NEDNSProxyProvider {

  override func startProxy(options: [String: Any]? = nil) async throws {
    handleLog("Start Proxy")
  }

  override func stopProxy(with reason: NEProviderStopReason) async {
    handleLog("Stop Proxy")
  }

  override func sleep() async {
    handleLog("Sleep Proxy")
  }

  override func wake() {
    handleLog("Wake Proxy")
  }

  override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
    guard let url = flow.remoteHostname else {
      handleLog("Flow without remoteHostname, dropping...", .warn)
      return false
    }

    if let udpFlow = flow as? NEAppProxyUDPFlow {
      handleUDPFlow(udpFlow, url)
      return true

    } else {
      handleLog("Unsupported flow that is not UDP for \(url)", .warn)
    }
    return false
  }
}

func handleUDPFlow(_ flow: NEAppProxyUDPFlow, _ url: String) {
  Task {
    do {
      handleLog("Open UDP flow for \(url)")
      try await flow.open(withLocalFlowEndpoint: nil)
      var counter = 0

      // TODO: Problem: This post https://developer.apple.com/forums/thread/772657?page=2#861318022 suggests that we should keep reading from the flow in a loop
      // However, we never actually receive data on the same flow again, so I don't think this is correct.
      while true {
        counter += 1
        do {
          let (datagrams, error) = await flow.readDatagrams()
          if let error = error {
            throw (error)
          }

          // if the datagrams are nil we throw an error; this it not supposed to happen as we expect that this is only nil if the error is not nil
          guard let datagrams = datagrams else {
            throw (InternalError.noDatagrams)
          }

          if datagrams.isEmpty {
            // TODO: Problem: We add a one second sleep because otherwise when there is no datagrams to read (i.e. empty array) there is a busy loop with constant high CPU.
            try await Task.sleep(nanoseconds: 1_000_000_000)

            continue
          }

          if counter > 1 {
            handleLog("Received more than one request on one flow", .debug)
          }

          // TODO: Theoretically there could be more than one datagram from the read (and we would have to handle muliple datagram in a loop), but we never actually see a flow where this happens.
          if datagrams.count > 1 {
            handleLog(
              "Unexpected read of more than 1 datagram from flow for \(url); falling back to first datagram",
              .debug)
          }

          let remote = datagrams[0].1
          let data = datagrams[0].0

          let classesAndTypes = try extractClassAndTypeFromDnsQuestionDnsUtil(data)

          if classesAndTypes.isEmpty {
            throw InternalError.noClassType
          } else if classesAndTypes.count > 1 {
            // possible but not expected
            handleLog(
              "Unexpected DNS query with more than one question for url \(url): \(classesAndTypes)",
              .warn)
          } else {
            handleLog(
              "DNS query for url \(url) has class \(classesAndTypes[0].0) and type \(classesAndTypes[0].1)"
            )
          }

          Task {
            do {
              let reply = try await resolveWithUpstream(
                data, dnsIpAddress: "8.8.8.8", dnsPort: 53)

              let answers = try extractAnswersFromDnsReplyDnsUtil(reply)
              for answer in answers {
                handleLog(
                  "  Resolved answer \(answer) for \(url) with class \(classesAndTypes[0].0) and type \(classesAndTypes[0].1)"
                )
              }

              try await flow.writeDatagrams([(reply, remote)])
              handleLog(
                "Wrote reply to UDP flow for query for \(url) with class \(classesAndTypes[0].0) and type \(classesAndTypes[0].1)"
              )
            } catch {
              handleLog(
                "Failed to handle lookup/write for UDP flow for \(url), closed with error: \(error)",
                .error)
            }
          }

        } catch {
          flow.closeReadWithError(error)
          flow.closeWriteWithError(error)
          handleLog("Failed to read from UDP flow for \(url), closed with error: \(error)", .error)
        }
      }

      handleLog("Flow for \(url) finished, closing without error")

      flow.closeReadWithError(nil)
      flow.closeWriteWithError(nil)
    } catch {
      flow.closeReadWithError(error)
      flow.closeWriteWithError(error)
      handleLog("Failed to open UDP flow for \(url), closed with error: \(error)", .error)
    }
  }
}

func resolveWithUpstream(
  _ query: Data, dnsIpAddress: String, dnsPort: Int
) async throws -> Data {
  let connection = try await newConnection(host: dnsIpAddress, port: dnsPort)
  do {
    try await connection.sendAsync(content: query)

    let reply = try await connection.receiveMessageAsync()

    connection.cancel()

    guard let reply = reply else {
      throw InternalError.noDnsResponse
    }

    return reply
  } catch {
    handleLog("Error when handling connection: \(error)", .error)
    connection.cancel()
    throw error
  }
}

func newConnection(host: String, port: Int) async throws -> NWConnection {
  let connection = NWConnection(
    host: Network.NWEndpoint.Host(host),
    port: Network.NWEndpoint.Port(rawValue: UInt16(port))!, using: .udp)

  do {
    try await connection.establish()
  } catch {
    connection.cancel()
    handleLog(
      "Failed to establish connection with upstream DNS server: \(error.localizedDescription)",
      .error)
    throw error
  }

  return connection
}

func handleLog(_ message: String, _ level: LogLevel = LogLevel.info) {
  #if DEBUG
  #else
    // Release build won't print on debug
    if level == .debug {
      return
    }
  #endif

  os_log("%{public}@", type: level.toOSLogType, "\(message)")
}

enum LogLevel: String {
  case error = "error"
  case warn = "warn"
  case info = "info"
  case debug = "debug"
}

extension LogLevel {
  /// Converts the custom LogLevel to the corresponding OSLogType.
  /// This mapping aims to provide the closest equivalent OSLogType for common logging scenarios.
  var toOSLogType: OSLogType {
    switch self {
    case .debug:
      return .debug
    case .info:
      return .info
    case .warn:
      // OSLogType does not have a direct "warning" equivalent.
      // .info or .default could be used, but .error is often chosen
      // for warnings that indicate potential issues, even if not critical.
      // A common practice is to map warnings to .error if you want them to be easily visible.
      return .error
    case .error:
      return .error
    }
  }
}

enum InternalError: Error, Sendable {
  static let domain = "com.saasyan.test"

  case noDnsResponse
  case dnsQueryMalformd
  case noDatagrams
  case noClassType

  case invalidDnsTransactionId
  case dnsParseFailed
  case dnsInvalidNoQuestion
  case dnsQuestionParseFailed
  case noAnwsersInDnsResponse

  case network(any Error)

  func description() -> [String: Any]? {
    switch self {
    case .noDnsResponse:
      return [NSLocalizedDescriptionKey: "Upstream DNS server did not return data"]
    case .noDatagrams:
      return [NSLocalizedDescriptionKey: "No datagrams in flow"]
    case .noClassType:
      return [
        NSLocalizedDescriptionKey:
          "Not expected to parse for class and types and receive an empty array"
      ]
    case .dnsQueryMalformd:
      return [NSLocalizedDescriptionKey: "Malformed DNS query"]
    case .network(let error):
      return [NSLocalizedDescriptionKey: error.localizedDescription]
    case .invalidDnsTransactionId:
      return [NSLocalizedDescriptionKey: "Invalid DNS transaction ID"]
    case .dnsParseFailed:
      return [NSLocalizedDescriptionKey: "Failed to parse DNS message"]
    case .dnsInvalidNoQuestion:
      return [NSLocalizedDescriptionKey: "DNS query does not have a question"]
    case .dnsQuestionParseFailed:
      return [NSLocalizedDescriptionKey: "Failed to extract question from DNS message"]
    case .noAnwsersInDnsResponse:
      return [NSLocalizedDescriptionKey: "No answers in DNS reply"]
    }
  }
}
