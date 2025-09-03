//
//  ContentView.swift
//  NEDNSProxyTest
//
//  Created by Daniel Karzel on 3/9/2025.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack {
      Image(systemName: "globe")
        .imageScale(.large)
        .foregroundStyle(.tint)
      Text(
        "With configuration profile in place the DNS proxy should be automtically turn to 'Running'!"
      )
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
