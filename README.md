# MWE-NEDNSProxyProvider

Minimal Working Example in Swift to showcase instability issues with [`NEDNSProxyProvider`](https://developer.apple.com/documentation/networkextension/nednsproxyprovider).

We deployed the code in this repo https://github.com/iharandreyev/dnsproxy.ios.example on the same devices and encountered the same issues.

## Test device setup

1. We use _supervised_ devices for testing.
2. The DNS Proxy is enforced by a configuration profile (we push that from JAMF Pro).
   1. Sample configuration profile to configure the DNS proxy is provided in [MWE-DNSProxyProvider.mobileconfig](MWE-DNSProxyProvider.mobileconfig)

When we deployed the code of https://github.com/iharandreyev/dnsproxy.ios.example we used the manual configuration.
For configuring the DNS proxy manually you can have a look at the use of `NEDNSProxyManager` in that project.
In order to keep our minimal working example minimal we provide the configuration profile for enforcing the proxy.

We tested on two iPads:

1. iPad generation 9, iPad OS version: `18.6.2`
2. iPad generation 10, iPad OS version: `18.6.2`

Note: We tested with several 18.x versions prior to the one above and encountered the same issues.

## Project setup

`NEDNSProxyTest` XCode project with two targets

- `NEDNSProxyTest`: host app that installs the extension on first start
- `NEDnsProxyTest-Extension`: DNSProxy extension

Notes:

1. Uses Swift 6
2. Uses Swift concurrency; including the `async/await` interface for `NEDNSProxyProvider`'s `startProxy` and `stopProxy`
   1. Note: Projects like https://github.com/iharandreyev/dnsproxy.ios.example still use GCD interface but add async/await wrappers, but that should not make a difference.

Basic steps of handling flows in this example repo:

1. Receive all DNS requests through `handleNewFlow`
2. Only handle UDP flows
   1. In this minimal example we only handle UDP.
   2. We have a more complete version where TCP is handled as well; but given the issues we see with UDP we omit the TCP code here.
3. Read query
4. Always use Google DNS (`8.8.8.8:53`) as upstream to resolve queries
   1. Omitted in this example repo but might be relevant for overall assessment:
      1. We also tested with using the system-assigned DNS server (same issues), but always using Google DNS is more reliable for testing.
      2. We have a more complete version with caching where we would not always go to the remote but return cached results.
         1. Even when the reply is returned from cache we see sporadic issues with hangs (see issue section below)
5. Write reply
6. Close flow with / without error

## Instability issues

If you just run the project for simple testing it will likely work; i.e. if you just deploy and open one web-page once the proxy will likely work.

But, when running it longer we encountered weird behaviour:

1. Browser tab would "hangs" (page kees loading until eventual timeout) even thought the extension sent a reply and closed the flow
   1. This would typically only concern some tabs (with some domains)
      1. e.g. tab with `linkedin.com` would hang, but tab with `google.com` still loads
      2. We monitor the incoming DNS packets for types to see if there is a pattern. We could not see a pattern, the replies from the upstream Google DNS was always written in the glow.
   2. We tested with multiple browsers (Safari, Chrome, Firefox)
      1. It has often happened that when a domain was hanging in one browser it is also hanging in the other browser, but there was no consistent pattern there.
   3. It's very unpredictable how long the issue persists
      1. Sometimes this resolves itself quite fast (i.e. hangs, times out, open another tab or reload, works)
      2. Sometimes it would not work for longer periods of time (i.e. > 5 minutes) - but typically only for certain domains.
   4. When attaching to the process and following the logs we see that the network extension is doing its job - replies are sent
      1. We monitored the incoming flows and the replies, and the extension handles them timely.
      2. Profiling hangs with Instruments revealed some WebKit hangs, but we could not consistently map those to the observed hang behaviour in the browser.
2. Sometimes the memory "jumps up". We could not derive any patterns to when/why this happens.
   1. At times, it would run for long time (>24h) with stable memory and usage (attached regularly to the process with XCode to check)
   2. Typically, the memory hovers around 3.1 MB once `startProxy` has been called.
      1. Under load (i.e. open multiple tabs in browser in short interval) the memory might go up to ~4.x-5 MB but then fall down to the baseline fo 3.1 again.
   3. Sometimes the memory jumps to ~7.x MB after startup
      1. If this happens the memory would stay this high as baseline.
      2. We have not found any patterns to correlate why this happens.
   4. Sometimes the memory jumps up (and then does not go down to the baseline again)
      1. This has happened very rarely, typically the memory would only temporarily go up and then fallback down to the baseline after ~2 minutes.
      2. If a sudden jump over ~7MB happens the memory would not go down to the baseline again.
      3. This issue might be the same as when this happens at startup, but we could not pinpoint it, so I'm mentioning that it also sporadically happened during longer operation.
   5. We profiled for leaks, but the Instruments leak profiler did not reveal any.

Other notes:

1. We could not derive any patterns related to start/stop or sleep/wake.
2. We could not derive patterns related to being attached to the process for profiling or not. (When profiling e.g. memory leaks the baseline memory is slightly higher, but that should be normal)
3. We could not derive patterns related to debug/release builds; we tested with both debug and release builds.
