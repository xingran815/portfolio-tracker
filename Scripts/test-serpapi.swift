#!/usr/bin/env swift
//
// Quick test script for SerpAPI
// Run: swift Scripts/test-serpapi.swift
//

import Foundation

print("🧪 Testing SerpAPI...")
print("================================")

// Get API key from environment
let apiKey = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"] ?? ""

if apiKey.isEmpty {
    print("❌ No API key found!")
    print("Set your API key:")
    print("  export SERPAPI_API_KEY=your-key-here")
    exit(1)
}

// Test search query
let searchQuery = "2026年至今中国A股走势"
let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery

let urlString = "https://serpapi.com/search.json?q=\(encodedQuery)&api_key=\(apiKey)&hl=zh-cn&gl=cn"

guard let url = URL(string: urlString) else {
    print("❌ Invalid URL")
    exit(1)
}

var request = URLRequest(url: url)
request.httpMethod = "GET"

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
    
    if let error = json["error"] as? String {
        print("❌ API Error: \(error)")
        exit(1)
    }
    
    print("✅ Success!")
    print("")
    
    if let searchMetadata = json["search_metadata"] as? [String: Any],
       let status = searchMetadata["status"] as? String {
        print("📊 Status: \(status)")
    }
    
    if let totalResults = json["search_information"] as? [String: Any],
       let total = totalResults["total_results"] as? Int {
        print("📈 Total results: \(total)")
        print("")
    }
    
    if let organicResults = json["organic_results"] as? [[String: Any]] {
        print("🔍 Top Results (\(organicResults.count) found):")
        for (index, result) in organicResults.prefix(5).enumerated() {
            let title = result["title"] as? String ?? "No title"
            let link = result["link"] as? String ?? "No URL"
            let snippet = result["snippet"] as? String ?? ""
            
            print("   \(index + 1). \(title)")
            print("      URL: \(link)")
            if !snippet.isEmpty {
                print("      Snippet: \(snippet.prefix(100))...")
            }
            print("")
        }
    }
}

task.resume()

semaphore.wait()
