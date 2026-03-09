#!/usr/bin/env swift
//
// Final test for Kimi Coding API with correct headers
//

import Foundation

print("🧪 Testing Kimi Coding API (Final)")
print("===================================")
print("Endpoint: https://api.kimi.com/coding/v1")
print("Headers: User-Agent: claude-code/1.0, X-Client-Name: claude-code")
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

print("✅ API key retrieved: \(apiKey.prefix(15))...")
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
request.setValue("claude-code/1.0", forHTTPHeaderField: "User-Agent")
request.setValue("claude-code", forHTTPHeaderField: "X-Client-Name")

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
                print("   Model: \(json["model"] as? String ?? "unknown")")
                print("   Response: \(content.isEmpty ? "(empty - may have reasoning)" : content)")
                
                // Show reasoning if available
                if let reasoning = message["reasoning_content"] as? String {
                    print("")
                    print("🧠 Reasoning: \(reasoning.prefix(100))...")
                }
                
                print("")
                print("🎉 Kimi Coding API is working!")
                
            } else if let error = json["error"] as? [String: Any],
                      let message = error["message"] as? String {
                print("❌ API Error: \(message)")
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
