#!/usr/bin/env swift
//
// Test Kimi API with real key
// Supports both Moonshot (platform.moonshot.cn) and Kimi Web (kimi.com)
//
// Usage:
//   swift Scripts/test-kimi.swift moonshot    # For platform.moonshot.cn keys
//   swift Scripts/test-kimi.swift kimi        # For kimi.com keys

import Foundation

print("🧪 Testing Kimi API...")
print("=====================")

// Determine endpoint from argument
let endpointArg = CommandLine.arguments.dropFirst().first ?? "moonshot"
let isKimiWeb = endpointArg == "kimi"

print("📍 Endpoint: \(isKimiWeb ? "kimi.com" : "platform.moonshot.cn")")

// Get API key from Keychain
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
    print("❌ Kimi API key not found in Keychain")
    print("   Add it to .env.local and run: ./Scripts/setup-api-keys.sh")
    exit(1)
}

print("✅ API key retrieved")

// Try different authentication methods
let authMethods = isKimiWeb ? [
    ("x-api-key header", "x-api-key"),
    ("Authorization: Api-Key", "Api-Key"),
    ("Authorization: Bearer", "Bearer")
] : [
    ("Authorization: Bearer", "Bearer")
]

for (authName, authPrefix) in authMethods {
    print("")
    print("🔐 Trying authentication: \(authName)")
    print("📡 Sending test message...")
    
    let baseURL = isKimiWeb ? "https://kimi.com/api/v1" : "https://api.moonshot.cn/v1"
    let url = URL(string: "\(baseURL)/chat/completions")!
    
    let requestBody: [String: Any] = [
        "model": isKimiWeb ? "kimi-latest" : "moonshot-v1-8k",
        "messages": [
            ["role": "user", "content": "Hello! Briefly introduce yourself in one sentence."]
        ],
        "temperature": 0.7,
        "max_tokens": 100,
        "stream": false  // Non-streaming for easier testing
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    // Set authentication header
    if authPrefix == "x-api-key" {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    } else {
        request.setValue("\(authPrefix) \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    
    request.httpBody = try! JSONSerialization.data(withJSONObject: requestBody)
    
    let semaphore = DispatchSemaphore(value: 0)
    var success = false
    
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
                    
                    print("")
                    print("✅ SUCCESS with \(authName)!")
                    print("   Response: \(content)")
                    success = true
                    
                } else if let error = json["error"] as? [String: Any],
                          let message = error["message"] as? String {
                    print("❌ API Error: \(message)")
                    
                    // Print full response for debugging
                    print("   Full response:")
                    if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        print(jsonString.prefix(500))
                    }
                } else {
                    print("Response:")
                    print(String(data: data, encoding: .utf8) ?? "Invalid")
                }
            }
        } catch {
            print("❌ JSON error: \(error)")
        }
    }
    
    task.resume()
    _ = semaphore.wait(timeout: .now() + 30)
    
    if success {
        print("")
        print("🎉 Kimi API is working!")
        print("   Use auth method: \(authName)")
        break
    }
}

if !isKimiWeb {
    print("")
    print("💡 If this fails, your key might be from kimi.com instead of platform.moonshot.cn")
    print("   Try: swift Scripts/test-kimi.swift kimi")
}
