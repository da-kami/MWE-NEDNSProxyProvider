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

      let (datagrams, error) = await flow.readDatagrams()
      if let error = error {
        throw (error)
      }

      guard let datagrams = datagrams else {
        throw (InternalError.noDatagrams)
      }

      if datagrams.count != 1 {
        throw InternalError.dnsQueryMalformd
      }

      let remote = datagrams[0].1
      let reply = try await resolveWithUpstream(
        datagrams[0].0, dnsIpAddress: "8.8.8.8", dnsPort: 53)

      try await flow.writeDatagrams([(reply, remote)])
      handleLog("Wrote reply to UDP flow for \(url)")

      flow.closeReadWithError(nil)
      flow.closeWriteWithError(nil)
    } catch {
      flow.closeReadWithError(error)
      flow.closeWriteWithError(error)
      handleLog("UDP flow for \(url) closed with error: \(error)", .error)
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

  case network(any Error)

  func description() -> [String: Any]? {
    switch self {
    case .noDnsResponse:
      return [NSLocalizedDescriptionKey: "Upstream DNS server did not return data"]
    case .noDatagrams:
      return [NSLocalizedDescriptionKey: "No datagrams in flow"]
    case .dnsQueryMalformd:
      return [NSLocalizedDescriptionKey: "Malformed DNS query"]
    case .network(let error):
      return [NSLocalizedDescriptionKey: error.localizedDescription]
    }

  }
}
