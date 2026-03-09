#!/usr/bin/env swift
//
// Test Kimi API with Anthropic/JS User-Agent (as it works on other machines)
//

import Foundation

print("🧪 Testing Kimi API with Anthropic User-Agent")
print("==============================================")

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
    print("❌ API key not found")
    exit(1)
}

print("✅ Key: \(apiKey.prefix(15))...")
print("")

// Test with Anthropic User-Agent
let configurations = [
    ("Moonshot + Anthropic UA", "https://api.moonshot.cn/v1", "Anthropic/JS 0.73.0"),
    ("Moonshot + Anthropic Auth", "https://api.moonshot.cn/v1", "Anthropic-JavaScript/0.73.0"),
    ("Kimi Web + Anthropic UA", "https://kimi.com/api", "Anthropic/JS 0.73.0"),
    ("Kimi + x-api-key", "https://api.moonshot.cn/v1", nil),
]

for (configName, baseURL, userAgent) in configurations {
    let urlString = "\(baseURL)/chat/completions"
    guard let url = URL(string: urlString) else { continue }
    
    print("Testing: \(configName)")
    
    let requestBody: [String: Any] = [
        "model": "moonshot-v1-8k",
        "messages": [["role": "user", "content": "Hello"]],
        "max_tokens": 50,
        "stream": false
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    
    if let ua = userAgent {
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue(ua, forHTTPHeaderField: "X-Client-Name")
    }
    
    // Additional headers that might be needed
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    
    request.httpBody = try! JSONSerialization.data(withJSONObject: requestBody)
    
    let semaphore = DispatchSemaphore(value: 0)
    var success = false
    
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
                print("  Response: \(jsonString.prefix(300))")
                success = true
            } else {
                print("  Response: \(jsonString.prefix(300))")
            }
        }
    }
    
    task.resume()
    _ = semaphore.wait(timeout: .now() + 15)
    print("")
    
    if success {
        print("🎉 FOUND WORKING CONFIGURATION!")
        print("   Use: \(configName)")
        break
    }
}

print("")
print("If none worked, try checking:")
print("1. Does the key work with curl?")
print("2. Is there a specific origin header required?")
print("3. Is the key tied to a specific IP/domain?")
