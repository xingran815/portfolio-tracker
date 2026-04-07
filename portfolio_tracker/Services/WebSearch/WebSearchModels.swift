//
//  WebSearchModels.swift
//  portfolio_tracker
//
//  Data models for web search functionality
//

import Foundation

struct TavilySearchOptions: Sendable {
    let maxResults: Int
    let searchDepth: String
    let includeAnswer: Bool
    let topic: String
    let timeRange: String?
    
    static let `default` = TavilySearchOptions(
        maxResults: 5,
        searchDepth: "basic",
        includeAnswer: true,
        topic: "finance",
        timeRange: nil
    )
    
    static let news = TavilySearchOptions(
        maxResults: 5,
        searchDepth: "basic",
        includeAnswer: true,
        topic: "news",
        timeRange: "week"
    )
}

struct TavilySearchResult: Sendable {
    let query: String
    let answer: String?
    let results: [TavilySearchResultItem]
    let responseTime: Double
    
    var hasResults: Bool {
        !results.isEmpty
    }
    
    func toSystemPromptContext() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let searchDate = dateFormatter.string(from: Date())
        
        var output = """
        
        
        ════════════════════════════════════════════════════════════
        WEB SEARCH RESULTS (Retrieved: \(searchDate))
        ════════════════════════════════════════════════════════════
        Query: \(query)
        
        """
        
        if let answer = answer, !answer.isEmpty {
            output += """
            **AI-Generated Summary:**
            \(answer)
            
            """
        }
        
        output += "**Search Results:**\n\n"
        
        for (index, item) in results.enumerated() {
            let truncatedContent = Self.truncateAtSentence(item.content, maxLength: 800)
            
            output += """
            [\(index + 1)] \(item.title)
            \(truncatedContent)
            Source: \(item.url)
            
            """
        }
        
        output += """
        ════════════════════════════════════════════════════════════
        **CRITICAL INSTRUCTIONS:**
        - You MUST use the information from the search results above
        - This is REAL-TIME data retrieved on \(searchDate)
        - This information supersedes your training data
        - NEVER say "I cannot access current information" when these results are provided
        - ALWAYS cite sources using [1], [2], [3] format in your response
        - Example: "According to recent data, AAPL is trading at $180 [1]"
        ════════════════════════════════════════════════════════════
        
        """
        return output
    }
    
    private static func truncateAtSentence(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        
        let prefix = String(text.prefix(maxLength))
        
        let sentenceEnders = [".", "?", "!", "。", "？", "！"]
        var lastSentenceEnd = prefix.endIndex
        
        for ender in sentenceEnders {
            if let range = prefix.range(of: ender, options: .backwards) {
                if range.upperBound < lastSentenceEnd {
                    lastSentenceEnd = range.upperBound
                }
            }
        }
        
        if lastSentenceEnd < prefix.endIndex {
            return String(prefix[..<lastSentenceEnd])
        }
        
        return prefix + "..."
    }
}

struct TavilySearchResultItem: Sendable, Codable {
    let title: String
    let url: String
    let content: String
    let score: Double
    let publishedDate: String?
    
    private enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}

struct TavilyAPIResponse: Codable {
    let query: String
    let answer: String?
    let results: [TavilySearchResultItem]
    let responseTime: Double
    
    private enum CodingKeys: String, CodingKey {
        case query
        case answer
        case results
        case responseTime = "response_time"
    }
}

struct TavilyAPIError: Codable {
    let detail: TavilyErrorDetail?
}

struct TavilyErrorDetail: Codable {
    let error: String?
}
