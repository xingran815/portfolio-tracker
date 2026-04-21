//
//  WebSearchModels.swift
//  portfolio_tracker
//
//  Data models for web search functionality
//

import Foundation

// MARK: - SerpAPI Models

struct SerpAPIResponse: Codable {
    let searchMetadata: SerpSearchMetadata?
    let searchParameters: SerpSearchParameters?
    let searchInformation: SerpSearchInformation?
    let organicResults: [SerpOrganicResult]?
    let relatedQuestions: [SerpRelatedQuestion]?
    let knowledgeGraph: SerpKnowledgeGraph?
    
    private enum CodingKeys: String, CodingKey {
        case searchMetadata = "search_metadata"
        case searchParameters = "search_parameters"
        case searchInformation = "search_information"
        case organicResults = "organic_results"
        case relatedQuestions = "related_questions"
        case knowledgeGraph = "knowledge_graph"
    }
}

struct SerpSearchMetadata: Codable {
    let id: String?
    let status: String?
    let createdAt: String?
    let processedAt: String?
    let totalTimeTaken: Double?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt = "created_at"
        case processedAt = "processed_at"
        case totalTimeTaken = "total_time_taken"
    }
}

struct SerpSearchParameters: Codable {
    let engine: String?
    let q: String?
    let googleDomain: String?
    let hl: String?
    let gl: String?
    
    private enum CodingKeys: String, CodingKey {
        case engine
        case q
        case googleDomain = "google_domain"
        case hl
        case gl
    }
}

struct SerpSearchInformation: Codable {
    let queryDisplayed: String?
    let totalResults: Int?
    let timeTaken: Double?
    
    private enum CodingKeys: String, CodingKey {
        case queryDisplayed = "query_displayed"
        case totalResults = "total_results"
        case timeTaken = "time_taken_displayed"
    }
}

struct SerpOrganicResult: Codable {
    let position: Int?
    let title: String?
    let link: String?
    let displayedLink: String?
    let snippet: String?
    let date: String?
    
    private enum CodingKeys: String, CodingKey {
        case position
        case title
        case link
        case displayedLink = "displayed_link"
        case snippet
        case date
    }
}

struct SerpRelatedQuestion: Codable {
    let question: String?
    let snippet: String?
    let title: String?
    let link: String?
}

struct SerpKnowledgeGraph: Codable {
    let title: String?
    let type: String?
    let description: String?
    let source: SerpKGSource?
    
    private enum CodingKeys: String, CodingKey {
        case title
        case type
        case description
        case source
    }
}

struct SerpKGSource: Codable {
    let name: String?
    let link: String?
}

struct SerpAPIErrorResponse: Codable {
    let error: String?
}

struct SerpSearchResult: Sendable {
    let query: String
    let results: [SerpSearchResultItem]
    let totalResults: Int?
    let searchTime: Double?
    
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
        
        **Search Results:**
        
        """
        
        for (index, item) in results.enumerated() {
            let truncatedContent = Self.truncateAtSentence(item.snippet, maxLength: 800)
            
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

struct SerpSearchResultItem: Sendable {
    let title: String
    let url: String
    let snippet: String
    let position: Int
}
