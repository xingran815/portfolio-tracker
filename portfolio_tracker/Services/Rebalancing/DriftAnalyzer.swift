//
//  DriftAnalyzer.swift
//  portfolio_tracker
//
//  Portfolio drift analysis from target allocation
//

import Foundation

// MARK: - Analysis Constants

/// Constants for drift analysis calculations
enum DriftAnalysisConstants {
    /// Default drift threshold (5%)
    static let defaultThreshold: Double = 0.05
    
    /// Epsilon for floating point comparisons
    static let epsilon: Double = 1e-10
    
    /// Tolerance for considering allocation as normalized (1%)
    static let normalizationTolerance: Double = 0.01
    
    /// Minimum weight to avoid division issues
    static let minWeight: Double = 1e-10
}

// MARK: - Drift Types

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
        drift > DriftAnalysisConstants.epsilon
    }
    
    /// Whether position is underweight
    var isUnderweight: Bool {
        drift < -DriftAnalysisConstants.epsilon
    }
    
    /// Value adjustment needed to reach target (nil if cannot calculate)
    var adjustmentValue: Double? {
        // Guard against division by zero
        guard currentWeight > DriftAnalysisConstants.minWeight else {
            // For positions with no current weight, calculate based on total
            return nil
        }
        return drift * (currentValue / currentWeight)
    }
    
    /// Formatted description
    var description: String {
        let direction = isOverweight ? "Overweight" : (isUnderweight ? "Underweight" : "On target")
        let pct = Int(absoluteDrift * 100)
        return "\(symbol): \(direction) by \(pct)%"
    }
}

// MARK: - Errors

enum DriftAnalysisError: LocalizedError, Sendable {
    case noPositions
    case invalidTargetAllocation
    case totalValueZero
    case totalValueNegative
    case allocationSumZero
    
    var errorDescription: String? {
        switch self {
        case .noPositions:
            return "Portfolio has no positions to analyze"
        case .invalidTargetAllocation:
            return "Target allocation is invalid or empty"
        case .totalValueZero:
            return "Portfolio total value is zero"
        case .totalValueNegative:
            return "Portfolio total value is negative"
        case .allocationSumZero:
            return "Target allocation sums to zero"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noPositions:
            return "Add positions to the portfolio before analyzing"
        case .invalidTargetAllocation:
            return "Set a target allocation in portfolio settings"
        case .totalValueZero, .totalValueNegative:
            return "Check that positions have valid prices and shares"
        case .allocationSumZero:
            return "Ensure target allocation percentages sum to 100%"
        }
    }
}

// MARK: - Analyzer

/// Analyzer for portfolio drift from target allocation
struct DriftAnalyzer: Sendable {
    
    /// Drift threshold for rebalancing trigger
    let threshold: Double
    
    /// Creates a drift analyzer
    /// - Parameter threshold: Drift threshold (default 5%)
    init(threshold: Double = DriftAnalysisConstants.defaultThreshold) {
        self.threshold = threshold
    }
    
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
        try validateInputs(positions: positions, targetAllocation: targetAllocation, totalValue: totalValue)
        
        // Normalize target allocation
        let normalizedTarget = try normalizeAllocation(targetAllocation)
        
        // Calculate drift for each position
        var positionDrifts: [PositionDrift] = []
        var totalAbsoluteDrift: Double = 0
        
        // Analyze existing positions
        for position in positions {
            let drift = calculateDrift(
                position: position,
                targetWeight: normalizedTarget[position.symbol ?? ""] ?? 0,
                totalValue: totalValue
            )
            
            positionDrifts.append(drift)
            totalAbsoluteDrift += abs(drift.drift)
        }
        
        // Check for target positions not in current holdings
        let currentSymbols = Set(positions.compactMap { $0.symbol })
        for (symbol, targetWeight) in normalizedTarget {
            if !currentSymbols.contains(symbol) && targetWeight > DriftAnalysisConstants.epsilon {
                // Missing position that should be added
                let positionDrift = PositionDrift(
                    symbol: symbol,
                    currentValue: 0,
                    currentWeight: 0,
                    targetWeight: targetWeight,
                    drift: -targetWeight
                )
                
                positionDrifts.append(positionDrift)
                totalAbsoluteDrift += targetWeight
            }
        }
        
        // Sort by absolute drift (descending)
        positionDrifts.sort { $0.absoluteDrift > $1.absoluteDrift }
        
        // Calculate total drift
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
    
    // MARK: - Private Helpers
    
    private func validateInputs(
        positions: [Position],
        targetAllocation: [String: Double],
        totalValue: Double
    ) throws {
        guard !positions.isEmpty else {
            throw DriftAnalysisError.noPositions
        }
        
        guard !targetAllocation.isEmpty else {
            throw DriftAnalysisError.invalidTargetAllocation
        }
        
        guard totalValue > DriftAnalysisConstants.epsilon else {
            if totalValue < 0 {
                throw DriftAnalysisError.totalValueNegative
            }
            throw DriftAnalysisError.totalValueZero
        }
    }
    
    private func normalizeAllocation(_ allocation: [String: Double]) throws -> [String: Double] {
        let total = allocation.values.reduce(0, +)
        
        guard total > DriftAnalysisConstants.epsilon else {
            throw DriftAnalysisError.allocationSumZero
        }
        
        // If total is already close to 1.0, return as-is
        if abs(total - 1.0) < DriftAnalysisConstants.normalizationTolerance {
            return allocation
        }
        
        // Normalize to sum to 1.0
        return allocation.mapValues { $0 / total }
    }
    
    private func calculateDrift(
        position: Position,
        targetWeight: Double,
        totalValue: Double
    ) -> PositionDrift {
        let symbol = position.symbol ?? "Unknown"
        let currentValue = position.currentValue ?? 0
        let currentWeight = totalValue > 0 ? currentValue / totalValue : 0
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

// MARK: - Extensions

extension DriftAnalysis {
    
    /// Positions that are overweight
    var overweightPositions: [PositionDrift] {
        positions.filter { $0.isOverweight }
    }
    
    /// Positions that are underweight
    var underweightPositions: [PositionDrift] {
        positions.filter { $0.isUnderweight }
    }
    
    /// Positions exceeding the threshold
    var significantDrifts: [PositionDrift] {
        positions.filter { $0.absoluteDrift > threshold }
    }
    
    /// Formatted summary string
    var summary: String {
        var lines: [String] = []
        lines.append("Drift Analysis (\(Int(threshold * 100))% threshold)")
        lines.append("Total Drift: \(String(format: "%.2f", totalDrift * 100))%")
        lines.append("Rebalancing Needed: \(needsRebalancing ? "Yes" : "No")")
        
        if !significantDrifts.isEmpty {
            lines.append("")
            lines.append("Significant Deviations:")
            for position in significantDrifts {
                lines.append("- \(position.description)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
