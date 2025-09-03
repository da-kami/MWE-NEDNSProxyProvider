//
//  DNSUtil.swift
//  NEDnsProxyTest-Extension
//
//  Created by Daniel Karzel on 3/9/2025.
//

import Foundation

/// https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-4
public enum DnsType: Int {
  case reserved = 0  // 65535
  case a = 1
  case ns = 2
  case md = 3
  case mf = 4
  case cname = 5
  case soa = 6
  case mb = 7
  case mg = 8
  case mr = 9
  case null = 10
  case wks = 11
  case ptr = 12
  case hinfo = 13
  case minfo = 14
  case mx = 15
  case txt = 16
  case rp = 17
  case afsdb = 18
  case x25 = 19
  case isdn = 20
  case rt = 21
  case nsap = 22
  case nsapptr = 23
  case sig = 24
  case key = 25
  case px = 26
  case gpos = 27
  case aaaa = 28
  case loc = 29
  case nxt = 30
  case eid = 31
  case nimloc = 32
  case srv = 33
  case atma = 34
  case naptr = 35
  case kx = 36
  case cert = 37
  case a6 = 38
  case dname = 39
  case sink = 40
  case opt = 41
  case apl = 42
  case ds = 43
  case sshfp = 44
  case ipseckey = 45
  case rrsig = 46
  case nsec = 47
  case dnskey = 48
  case dhcid = 49
  case nsec3 = 50
  case nsec3param = 51
  case tlsa = 52
  case smimea = 53
  case unassigned = 54  // 69-98, 110-127, 129-248, 265-32767, 32770-65279
  case hip = 55
  case ninfo = 56
  case rkey = 57
  case talink = 58
  case cds = 59
  case cdnskey = 60
  case openpgpkey = 61
  case csync = 62
  case zonemd = 63
  case svcb = 64
  case https = 65
  case dsync = 66
  case hhit = 67
  case brid = 68
  case spf = 99
  case uinfo = 100
  case uid = 101
  case gid = 102
  case unspec = 103
  case nid = 104
  case l32 = 105
  case l64 = 106
  case lp = 107
  case eui48 = 108
  case eui64 = 109
  case nxname = 128
  case tkey = 249
  case tsig = 250
  case ixfr = 251
  case axfr = 252
  case mailb = 253
  case maila = 254
  case star = 255
  case uri = 256
  case caa = 257
  case avc = 258
  case doa = 259
  case amtrelay = 260
  case resinfo = 261
  case wallet = 262
  case cla = 263
  case ipn = 264
  case ta = 32768
  case dlv = 32769
  case priv = 65280  // -65534
  case invalid = 65536
  case other = 65537  // used for cases where other libraries use "any" or "other"
  case compound = 65538  // used for cases where there are multiple types present

  public static func fromInt(t: Int) -> Self {
    let dnsType = DnsType(rawValue: t)

    if let dnsType {
      return dnsType
    }

    if t == 65535 {
      return DnsType.reserved
    }

    if t >= 65280 && t <= 65534 {
      return DnsType.priv
    }

    if t < 0 || t > 65535 {
      return DnsType.invalid
    }

    return DnsType.unassigned
  }
}

// https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-classes
public enum DnsClass: Int {
  case reserved = 0
  case internet = 1
  case unassigned = 2  // 5-253, 256-65279
  case chaos = 3
  case hesiod = 4
  case qclassNone = 254
  case qclassAny = 255
  case priv = 65280
  // Note: there are other cases, but we don't map all

  case invalid = 65536

  public static func fromInt(c: Int) -> Self {
    let dnsClass = DnsClass(rawValue: c)

    if let dnsClass {
      return dnsClass
    }

    if c >= 65280 && c <= 65534 {
      return DnsClass.priv
    }

    if c == 65535 {
      return DnsClass.reserved
    }

    if c < 0 || c > 65535 {
      return DnsClass.invalid
    }

    return DnsClass.unassigned
  }
}

func extractClassAndTypeFromDnsQuestionDnsUtil(_ message: Data) throws -> [(DnsClass, DnsType)] {
  let dnsPacket = try parseDnsMessageDnsUtil(message)

  defer {
    dns_free_reply(dnsPacket)
  }

  // Ensure there is at least one question in the query.
  guard dnsPacket.pointee.header.pointee.qdcount > 0 else {

    // Or handle the case of a query with no questions
    throw InternalError.dnsInvalidNoQuestion
  }

  let questions = UnsafeBufferPointer(
    start: dnsPacket.pointee.question, count: Int(dnsPacket.pointee.header.pointee.qdcount))

  if questions.count > 1 {
    handleLog(
      "Found DNS query with more than one question; returning type and class of first question",
      .warn)
  }

  var classesAndTypes: [(DnsClass, DnsType)] = []
  for question in questions {
    if question == nil {
      continue
    }

    let typeName = DnsType.fromInt(t: Int(question!.pointee.dnstype))
    let className = DnsClass.fromInt(c: Int(question!.pointee.dnsclass))
    classesAndTypes.append((className, typeName))
  }

  if classesAndTypes.isEmpty {
    throw InternalError.dnsQuestionParseFailed
  }

  return classesAndTypes
}

func extractAnswersFromDnsReplyDnsUtil(_ message: Data) throws -> [String] {
  let reply = try parseDnsMessageDnsUtil(message)

  defer {
    dns_free_reply(reply)
  }

  let answers = UnsafeBufferPointer(
    start: reply.pointee.answer, count: Int(reply.pointee.header.pointee.ancount))

  if !answers.isEmpty {
    var answerStrings = [String]()
    for answer in answers {
      if answer != nil {
        let answerString =
          "Name: \(answer!.pointee.name), TTL: \(answer!.pointee.ttl), Data: \(answer!.pointee.data)"

        answerStrings.append(answerString)
      }
    }

    return answerStrings
  } else {
    handleLog("DNS reply with no answer: \(message.map { String(format: "%02x", $0) }.joined())")
    return [String]()
  }
}

func parseDnsMessageDnsUtil(_ message: Data) throws -> UnsafeMutablePointer<dns_reply_t> {
  // libresolv packet parsing

  // 1. Define briding header

  // 2. Add libresolv as package

  // 3. Tell linker to use for build
  // Target Settings -> Build Phases -> Link Binary With Libraries -> Add libresolv.tbd library

  let replyQ = message.withUnsafeBytes { buf -> UnsafeMutablePointer<dns_reply_t>? in
    let base = buf.baseAddress!.assumingMemoryBound(to: Int8.self)
    return dns_parse_packet(base, UInt32(buf.count))
  }

  if replyQ != nil {
    return replyQ!
  } else {
    throw InternalError.dnsParseFailed
  }
}
