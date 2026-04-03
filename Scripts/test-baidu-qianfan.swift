#!/usr/bin/env swift

//
//  test-baidu-qianfan.swift
//  portfolio_tracker
//
//  Quick test script for Baidu Qianfan API
//  Run with: swift Scripts/test-baidu-qianfan.swift
//

import Foundation

// Read API key from keychain
func readAPIKey() -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    task.arguments = [
        "find-generic-password",
        "-a", "com.portfolio_tracker.baiduqianfan",
        "-s", "com.portfolio_tracker.apikeys",
        "-w"
    ]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } catch {
        print("❌ Error reading API key: \(error)")
    }
    
    return nil
}

// Test non-streaming request
func testNonStreaming(apiKey: String, model: String) async {
    print("\n🧪 Testing Non-Streaming Request (model: \(model))...")
    
    let url = URL(string: "https://qianfan.baidubce.com/v2/coding/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = [
        "model": model,
        "messages": [["role": "user", "content": "Hello! Say hello in one sentence."]],
        "max_tokens": 100
    ]
    
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("   Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("   ✅ Response: \(content)")
                } else {
                    print("   ❌ Failed to parse response")
                }
            } else {
                print("   ❌ HTTP Error: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Response: \(responseString)")
                }
            }
        }
    } catch {
        print("   ❌ Error: \(error)")
    }
}

// Test streaming request
func testStreaming(apiKey: String, model: String) async {
    print("\n🧪 Testing Streaming Request (model: \(model))...")
    
    let url = URL(string: "https://qianfan.baidubce.com/v2/coding/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = [
        "model": model,
        "messages": [["role": "user", "content": "Count from 1 to 5"]],
        "max_tokens": 100,
        "stream": true
    ]
    
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    
    do {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("   Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                var fullResponse = ""
                var chunkCount = 0
                
                for try await line in bytes.lines {
                    if line.hasPrefix("data: ") {
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { break }
                        
                        if let data = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            chunkCount += 1
                            fullResponse += content
                        }
                    }
                }
                
                print("   ✅ Received \(chunkCount) chunks")
                print("   ✅ Response: \(fullResponse)")
            } else {
                print("   ❌ HTTP Error: \(httpResponse.statusCode)")
            }
        }
    } catch {
        print("   ❌ Error: \(error)")
    }
}

// Test all models
func testAllModels(apiKey: String) async {
    print("\n🧪 Testing All Models...")
    
    let models = [
        ("kimi-k2.5", "Kimi-K2.5"),
        ("glm-5", "GLM-5"),
        ("minimax-m2.5", "MiniMax-M2.5")
    ]
    
    for (modelId, displayName) in models {
        print("\n--- Testing \(displayName) ---")
        await testNonStreaming(apiKey: apiKey, model: modelId)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second between tests
    }
}

// Main test runner
func main() async {
    print(String(repeating: "=", count: 60))
    print("Baidu Qianfan API Test Script")
    print(String(repeating: "=", count: 60))
    
    // Read API key
    guard let apiKey = readAPIKey() else {
        print("\n❌ API key not found in keychain")
        print("\nTo add API key, run:")
        print("  security add-generic-password \\")
        print("    -a \"com.portfolio_tracker.baiduqianfan\" \\")
        print("    -s \"com.portfolio_tracker.apikeys\" \\")
        print("    -w \"YOUR_API_KEY\"")
        exit(1)
    }
    
    print("\n✅ API key found: \(apiKey.prefix(20))...")
    
    // Run tests
    await testNonStreaming(apiKey: apiKey, model: "kimi-k2.5")
    await testStreaming(apiKey: apiKey, model: "kimi-k2.5")
    await testAllModels(apiKey: apiKey)
    
    print("\n" + String(repeating: "=", count: 60))
    print("✅ All tests complete!")
    print(String(repeating: "=", count: 60))
}

// Run main
Task {
    await main()
    exit(0)
}

RunLoop.main.run()
