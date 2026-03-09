//
//  DriftAnalyzer.swift
//  portfolio_tracker
//
//  Portfolio drift analysis from target allocation
//

import Foundation

/// Analysis result for portfolio drift
struct DriftAnalysis: Sendable {
    /// Total portfolio drift (sum of absolute deviations / 2)
    let totalDrift: Double
    
    /// Individual position drifts
    let positions: [PositionDrift]
    
    /// Whether rebalancing is recommended
    let needsRebalancing: Bool
    
    /// Threshold used for determination
    let threshold: Double
    
    /// Timestamp of analysis
    let timestamp: Date
}

/// Drift information for a single position
struct PositionDrift: Sendable {
    /// Stock symbol
    let symbol: String
    
    /// Current value of position
    let currentValue: Double
    
    /// Current weight in portfolio (0.0 - 1.0)
    let currentWeight: Double
    
    /// Target weight in portfolio (0.0 - 1.0)
    let targetWeight: Double
    
    /// Difference between current and target (current - target)
    let drift: Double
    
    /// Absolute drift amount
    var absoluteDrift: Double {
        abs(drift)
    }
    
    /// Whether position is overweight
    var isOverweight: Bool {
        drift > 0
    }
    
    /// Whether position is underweight
    var isUnderweight: Bool {
        drift < 0
    }
    
    /// Value adjustment needed to reach target
    var adjustmentValue: Double {
        drift * (currentValue / max(currentWeight, 0.0001))
    }
}

/// Errors that can occur during drift analysis
enum DriftAnalysisError: LocalizedError, Sendable {
    case noPositions
    case invalidTargetAllocation
    case totalValueZero
    
    var errorDescription: String? {
        switch self {
        case .noPositions:
            return "Portfolio has no positions to analyze"
        case .invalidTargetAllocation:
            return "Target allocation is invalid or empty"
        case .totalValueZero:
            return "Portfolio total value is zero"
        }
    }
}

/// Analyzer for portfolio drift from target allocation
struct DriftAnalyzer: Sendable {
    
    // MARK: - Properties
    
    /// Default drift threshold (5%)
    static let defaultThreshold: Double = 0.05
    
    /// Drift threshold for rebalancing trigger
    let threshold: Double
    
    // MARK: - Initialization
    
    /// Creates a drift analyzer
    /// - Parameter threshold: Drift threshold (default 5%)
    init(threshold: Double = defaultThreshold) {
        self.threshold = threshold
    }
    
    // MARK: - Public Methods
    
    /// Analyzes portfolio drift from target allocation
    /// - Parameters:
    ///   - positions: Current positions
    ///   - targetAllocation: Target allocation [symbol: weight]
    ///   - totalValue: Total portfolio value
    /// - Returns: Drift analysis result
    /// - Throws: DriftAnalysisError if analysis fails
    func analyze(
        positions: [Position],
        targetAllocation: [String: Double],
        totalValue: Double
    ) throws -> DriftAnalysis {
        // Validate inputs
        guard !positions.isEmpty else {
            throw DriftAnalysisError.noPositions
        }
        
        guard !targetAllocation.isEmpty else {
            throw DriftAnalysisError.invalidTargetAllocation
        }
        
        guard totalValue > 0 else {
            throw DriftAnalysisError.totalValueZero
        }
        
        // Normalize target allocation to ensure it sums to 1.0
        let normalizedTarget = normalizeAllocation(targetAllocation)
        
        // Calculate drift for each position
        var positionDrifts: [PositionDrift] = []
        var totalAbsoluteDrift: Double = 0
        
        // Analyze existing positions
        for position in positions {
            let symbol = position.symbol ?? "Unknown"
            let currentValue = position.currentValue ?? 0
            let currentWeight = currentValue / totalValue
            let targetWeight = normalizedTarget[symbol] ?? 0
            let drift = currentWeight - targetWeight
            
            let positionDrift = PositionDrift(
                symbol: symbol,
                currentValue: currentValue,
                currentWeight: currentWeight,
                targetWeight: targetWeight,
                drift: drift
            )
            
            positionDrifts.append(positionDrift)
            totalAbsoluteDrift += abs(drift)
        }
        
        // Check for target positions not in current holdings
        let currentSymbols = Set(positions.compactMap { $0.symbol })
        for (symbol, targetWeight) in normalizedTarget {
            if !currentSymbols.contains(symbol) && targetWeight > 0 {
                // Missing position that should be added
                let positionDrift = PositionDrift(
                    symbol: symbol,
                    currentValue: 0,
                    currentWeight: 0,
                    targetWeight: targetWeight,
                    drift: -targetWeight  // Negative = underweight (missing)
                )
                
                positionDrifts.append(positionDrift)
                totalAbsoluteDrift += targetWeight
            }
        }
        
        // Sort by absolute drift (descending)
        positionDrifts.sort { $0.absoluteDrift > $1.absoluteDrift }
        
        // Calculate total drift (sum of absolute deviations / 2)
        // Dividing by 2 because overweight in one position
        // must be balanced by underweight in others
        let totalDrift = totalAbsoluteDrift / 2
        
        // Determine if rebalancing is needed
        let needsRebalancing = positionDrifts.contains { $0.absoluteDrift > threshold }
        
        return DriftAnalysis(
            totalDrift: totalDrift,
            positions: positionDrifts,
            needsRebalancing: needsRebalancing,
            threshold: threshold,
            timestamp: Date()
        )
    }
    
    /// Quick check if rebalancing is needed
    /// - Parameters:
    ///   - positions: Current positions
    ///   - targetAllocation: Target allocation
    ///   - totalValue: Total portfolio value
    /// - Returns: True if any position exceeds threshold
    func needsRebalancing(
        positions: [Position],
        targetAllocation: [String: Double],
        totalValue: Double
    ) -> Bool {
        do {
            let analysis = try analyze(
                positions: positions,
                targetAllocation: targetAllocation,
                totalValue: totalValue
            )
            return analysis.needsRebalancing
        } catch {
            return false
        }
    }
    
    /// Calculates drift for a specific position
    /// - Parameters:
    ///   - position: Position to analyze
    ///   - targetWeight: Target weight for this position
    ///   - totalValue: Total portfolio value
    /// - Returns: Position drift info
    func analyzePosition(
        _ position: Position,
        targetWeight: Double,
        totalValue: Double
    ) -> PositionDrift? {
        guard totalValue > 0 else { return nil }
        
        let symbol = position.symbol ?? "Unknown"
        let currentValue = position.currentValue ?? 0
        let currentWeight = currentValue / totalValue
        let drift = currentWeight - targetWeight
        
        return PositionDrift(
            symbol: symbol,
            currentValue: currentValue,
            currentWeight: currentWeight,
            targetWeight: targetWeight,
            drift: drift
        )
    }
}

// MARK: - Private Helpers

private extension DriftAnalyzer {
    
    /// Normalizes allocation to sum to 1.0
    func normalizeAllocation(_ allocation: [String: Double]) -> [String: Double] {
        let total = allocation.values.reduce(0, +)
        guard total > 0 else { return allocation }
        
        // If total is already close to 1.0, return as-is
        if abs(total - 1.0) < 0.01 {
            return allocation
        }
        
        // Normalize to sum to 1.0
        return allocation.mapValues { $0 / total }
    }
}

// MARK: - Convenience Extensions

extension DriftAnalysis {
    
    /// Positions that are overweight (drift > 0)
    var overweightPositions: [PositionDrift] {
        positions.filter { $0.isOverweight }
    }
    
    /// Positions that are underweight (drift < 0)
    var underweightPositions: [PositionDrift] {
        positions.filter { $0.isUnderweight }
    }
    
    /// Positions exceeding the threshold
    var significantDrifts: [PositionDrift] {
        positions.filter { $0.absoluteDrift > threshold }
    }
    
    /// Formatted summary string
    var summary: String {
        var result = "Drift Analysis (\(Int(threshold * 100))% threshold)\n"
        result += "Total Drift: \(String(format: "%.2f", totalDrift * 100))%\n"
        result += "Rebalancing Needed: \(needsRebalancing ? "Yes" : "No")\n\n"
        
        result += "Significant Deviations:\n"
        for position in significantDrifts {
            let direction = position.isOverweight ? "Over" : "Under"
            result += "- \(position.symbol): \(direction) by \(String(format: "%.1f", position.absoluteDrift * 100))%\n"
        }
        
        return result
    }
}
