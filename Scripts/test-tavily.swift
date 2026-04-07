#!/usr/bin/env swift
//
// Quick test script for Tavily API
// Run: swift Scripts/test-tavily.swift
//

import Foundation

print("🧪 Testing Tavily API...")
print("================================")

// Get API key from environment
let apiKey = ProcessInfo.processInfo.environment["TAVILY_API_KEY"] ?? ""

if apiKey.isEmpty {
    print("❌ No API key found!")
    print("Set your API key:")
    print("  export TAVILY_API_KEY=tvly-your-key-here")
    exit(1)
}

// Test search query
let searchQuery = "Apple stock price today"

let url = URL(string: "https://api.tavily.com/search")!

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

let body: [String: Any] = [
    "query": searchQuery,
    "max_results": 3,
    "search_depth": "basic",
    "include_answer": true,
    "topic": "finance"
]

request.httpBody = try? JSONSerialization.data(withJSONObject: body)

print("📡 Searching for: \(searchQuery)...")

let semaphore = DispatchSemaphore(value: 0)

let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    
    if let error = error {
        print("❌ Error: \(error)")
        exit(1)
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
        print("❌ Invalid response")
        exit(1)
    }
    
    if httpResponse.statusCode == 401 {
        print("❌ Invalid API key (401 Unauthorized)")
        exit(1)
    }
    
    guard let data = data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("❌ Invalid response data")
        exit(1)
    }
    
    if let errorMsg = json["detail"] as? [String: Any],
       let error = errorMsg["error"] as? String {
        print("❌ API Error: \(error)")
        exit(1)
    }
    
    print("✅ Success!")
    print("")
    
    if let answer = json["answer"] as? String {
        print("🤖 AI Answer:")
        print("   \(answer)")
        print("")
    }
    
    if let results = json["results"] as? [[String: Any]] {
        print("🔍 Search Results (\(results.count) found):")
        for (index, result) in results.enumerated() {
            let title = result["title"] as? String ?? "No title"
            let url = result["url"] as? String ?? "No URL"
            let score = result["score"] as? Double ?? 0.0
            
            print("   \(index + 1). \(title)")
            print("      URL: \(url)")
            print("      Score: \(String(format: "%.2f", score))")
            print("")
        }
    }
    
    if let responseTime = json["response_time"] as? Double {
        print("⏱️  Response time: \(String(format: "%.2f", responseTime))s")
    }
}

task.resume()

semaphore.wait()
