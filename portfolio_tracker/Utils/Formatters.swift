//
//  Formatters.swift
//  portfolio_tracker
//
//  Formatting utilities
//

import Foundation

/// Shared formatters for consistent display
public enum Formatters {
    
    /// Currency formatter
    public static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    /// Percentage formatter
    public static let percentage: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
    
    /// Date formatter
    public static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    /// Date-time formatter
    public static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Number Extensions

extension Double {
    
    /// Formats as currency with symbol
    /// - Parameter currencyCode: ISO currency code (USD, CNY, etc.)
    /// - Returns: Formatted string
    public func formattedAsCurrency(currencyCode: String = "USD") -> String {
        let formatter = Formatters.currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
    
    /// Formats as percentage (0.08 -> 8.00%)
    public func formattedAsPercentage() -> String {
        Formatters.percentage.string(from: NSNumber(value: self)) ?? String(format: "%.2f%%", self * 100)
    }
    
    /// Formats as decimal with 2-4 digits
    public func formattedAsDecimal(maxDigits: Int = 4) -> String {
        String(format: "%.*f", maxDigits, self)
    }
}

// MARK: - Date Extensions

extension Date {
    
    /// Formats as medium date
    public func formattedAsDate() -> String {
        Formatters.date.string(from: self)
    }
    
    /// Formats as medium date + short time
    public func formattedAsDateTime() -> String {
        Formatters.dateTime.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    
    /// Truncates string to max length
    public func truncated(to length: Int, addEllipsis: Bool = true) -> String {
        if count <= length { return self }
        let endIndex = index(startIndex, offsetBy: length)
        let truncated = String(self[..<endIndex])
        return addEllipsis ? truncated + "..." : truncated
    }
}
