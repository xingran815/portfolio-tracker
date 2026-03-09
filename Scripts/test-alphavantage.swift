#!/usr/bin/env swift
//
// Quick test script for AlphaVantageProvider
// Run: swift Scripts/test-alphavantage.swift

import Foundation

// This is a simple test to verify your API key works
// It uses the Alpha Vantage API directly (not the app code)

print("🧪 Testing Alpha Vantage API...")
print("================================")

// Get API key from environment or Keychain
let apiKey = ProcessInfo.processInfo.environment["ALPHAVANTAGE_API_KEY"] ?? ""

if apiKey.isEmpty || apiKey == "your_key_here" {
    print("❌ No API key found!")
    print("Run: ./Scripts/setup-api-keys.sh")
    exit(1)
}

let symbol = "AAPL"
let urlString = "https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=\(symbol)&apikey=\(apiKey)"

guard let url = URL(string: urlString) else {
    print("❌ Invalid URL")
    exit(1)
}

print("📡 Fetching quote for \(symbol)...")

let task = URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
        print("❌ Error: \(error)")
        exit(1)
    }
    
    guard let data = data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("❌ Invalid response")
        exit(1)
    }
    
    if let quote = json["Global Quote"] as? [String: String],
       let price = quote["05. price"] {
        print("✅ Success!")
        print("   Symbol: \(symbol)")
        print("   Price: $\(price)")
    } else if let note = json["Note"] as? String {
        print("⚠️  API Limit: \(note)")
    } else if let errorMsg = json["Error Message"] as? String {
        print("❌ API Error: \(errorMsg)")
    } else {
        print("❌ Unexpected response: \(json)")
    }
    
    exit(0)
}

task.resume()

// Keep script running
RunLoop.main.run()
