#!/usr/bin/env swift
//
// Debug Kimi API with all possible endpoints and auth methods
//

import Foundation

print("🔍 Kimi API Debug Tool")
print("======================")

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
    print("❌ API key not found")
    exit(1)
}

print("✅ Key retrieved: \(apiKey.prefix(10))...\(apiKey.suffix(5))")
print("   Length: \(apiKey.count) chars")
print("")

// Test all endpoint variations
let endpoints = [
    ("Moonshot v1", "https://api.moonshot.cn/v1"),
    ("Moonshot cn", "https://api.moonshot.cn"),
    ("Kimi Web", "https://kimi.com/api"),
    ("Kimi Web v1", "https://kimi.com/api/v1"),
    ("Kimi Platform", "https://platform.moonshot.cn/v1"),
]

// Test all auth methods
let authMethods = [
    ("Bearer", "Bearer "),
    ("Api-Key", "Api-Key "),
    ("X-API-Key header only", nil),
]

var foundWorking = false

for (endpointName, baseURL) in endpoints {
    for (authName, authPrefix) in authMethods {
        if foundWorking { break }
        
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else { continue }
        
        print("Testing: \(endpointName) + \(authName)")
        print("  URL: \(urlString)")
        
        let requestBody: [String: Any] = [
            "model": "moonshot-v1-8k",
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 50,
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let prefix = authPrefix {
            request.setValue("\(prefix)\(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        request.httpBody = try! JSONSerialization.data(withJSONObject: requestBody)
        
        let semaphore = DispatchSemaphore(value: 0)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                print("  ❌ Error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("  ❌ Invalid response")
                return
            }
            
            print("  Status: \(httpResponse.statusCode)")
            
            if let data = data,
               let jsonString = String(data: data, encoding: .utf8) {
                if httpResponse.statusCode == 200 {
                    print("  ✅ SUCCESS!")
                    print("  Response: \(jsonString.prefix(200))")
                    foundWorking = true
                } else {
                    print("  Response: \(jsonString.prefix(200))")
                }
            }
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        print("")
    }
}

if !foundWorking {
    print("❌ No working combination found")
    print("")
    print("Possible issues:")
    print("1. Key may be expired or revoked")
    print("2. Account may need verification")
    print("3. Different endpoint required")
    print("")
    print("Try visiting: https://platform.moonshot.cn/console/api-keys")
    print("to verify your key is active")
}
