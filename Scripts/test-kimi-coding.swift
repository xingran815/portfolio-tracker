#!/usr/bin/env swift
//
// Test Kimi API with coding endpoint (https://api.kimi.com/coding/v1)
//

import Foundation

print("🧪 Testing Kimi Coding API")
print("==========================")
print("Endpoint: https://api.kimi.com/coding/v1")
print("")

// Get API key
let keychainQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.portfolio_tracker.apikeys",
    kSecAttrAccount as String: "com.portfolio_tracker.kimi",
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]

var result: AnyObject?
let status = SecItemCopyMatching(keychainQuery as CFDictionary, &result)

guard status == errSecSuccess,
      let keyData = result as? Data,
      let apiKey = String(data: keyData, encoding: .utf8) else {
    print("❌ API key not found in Keychain")
    exit(1)
}

print("✅ API key retrieved")
print("📡 Sending test request...")
print("")

let url = URL(string: "https://api.kimi.com/coding/v1/chat/completions")!

let requestBody: [String: Any] = [
    "model": "kimi-latest",
    "messages": [
        ["role": "user", "content": "Hello! Please introduce yourself briefly."]
    ],
    "temperature": 0.7,
    "max_tokens": 150,
    "stream": false
]

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("application/json", forHTTPHeaderField: "Accept")
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("Claude Code", forHTTPHeaderField: "User-Agent")

request.httpBody = try! JSONSerialization.data(withJSONObject: requestBody)

let semaphore = DispatchSemaphore(value: 0)

let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
    print("")
    
    guard let data = data else {
        print("❌ No data received")
        return
    }
    
    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if httpResponse.statusCode == 200,
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                print("✅ SUCCESS!")
                print("   Response: \(content)")
                print("")
                print("🎉 Kimi Coding API is working correctly!")
                
            } else if let error = json["error"] as? [String: Any],
                      let message = error["message"] as? String {
                print("❌ API Error: \(message)")
                print("")
                print("Full response:")
                print(String(data: data, encoding: .utf8) ?? "Invalid")
            } else {
                print("Response:")
                print(String(data: data, encoding: .utf8) ?? "Invalid")
            }
        }
    } catch {
        print("❌ JSON parsing error: \(error)")
    }
}

task.resume()
_ = semaphore.wait(timeout: .now() + 30)
