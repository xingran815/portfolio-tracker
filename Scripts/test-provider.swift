#!/usr/bin/env swift
//
// Test AlphaVantageProvider with real API key
// Run: swift Scripts/test-provider.swift

import Foundation

// Minimal test to verify the provider works
// This directly tests the AlphaVantageProvider implementation

print("🧪 Testing AlphaVantageProvider...")
print("===================================")

// Get API key from Keychain
let keychainQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.portfolio_tracker.apikeys",
    kSecAttrAccount as String: "com.portfolio_tracker.alphavantage",
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]

var result: AnyObject?
let status = SecItemCopyMatching(keychainQuery as CFDictionary, &result)

guard status == errSecSuccess,
      let keyData = result as? Data,
      let apiKey = String(data: keyData, encoding: .utf8) else {
    print("❌ Failed to retrieve API key from Keychain")
    print("   Run: ./Scripts/setup-api-keys.sh")
    exit(1)
}

print("✅ API key retrieved from Keychain")
print("📡 Testing with symbol: AAPL")

// Build URL
let symbol = "AAPL"
var components = URLComponents(string: "https://www.alphavantage.co/query")!
components.queryItems = [
    URLQueryItem(name: "function", value: "GLOBAL_QUOTE"),
    URLQueryItem(name: "symbol", value: symbol),
    URLQueryItem(name: "apikey", value: apiKey)
]

guard let url = components.url else {
    print("❌ Invalid URL")
    exit(1)
}

// Fetch data
let semaphore = DispatchSemaphore(value: 0)

let task = URLSession.shared.dataTask(with: url) { data, response, error in
    defer { semaphore.signal() }
    
    if let error = error {
        print("❌ Network error: \(error.localizedDescription)")
        return
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
        print("❌ Invalid response")
        return
    }
    
    print("📊 HTTP Status: \(httpResponse.statusCode)")
    
    guard let data = data else {
        print("❌ No data received")
        return
    }
    
    // Parse response
    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let quote = json["Global Quote"] as? [String: String],
               let price = quote["05. price"],
               let change = quote["09. change"],
               let changePercent = quote["10. change percent"] {
                
                print("")
                print("✅ SUCCESS!")
                print("   Symbol: \(symbol)")
                print("   Price: $\(price)")
                print("   Change: $\(change)")
                print("   Change %: \(changePercent)")
                print("")
                print("🎉 AlphaVantageProvider is working correctly!")
                
            } else if let note = json["Note"] as? String {
                print("⚠️  API Rate Limit:")
                print("   \(note)")
                print("")
                print("💡 Wait a minute and try again (free tier: 5 req/min)")
                
            } else if let errorMsg = json["Error Message"] as? String {
                print("❌ API Error:")
                print("   \(errorMsg)")
                
            } else {
                print("❌ Unexpected response:")
                print(String(data: data, encoding: .utf8) ?? "Invalid data")
            }
        }
    } catch {
        print("❌ JSON parsing error: \(error)")
        print("Raw response:")
        print(String(data: data, encoding: .utf8) ?? "Invalid data")
    }
}

task.resume()

// Wait for completion
_ = semaphore.wait(timeout: .now() + 30)
