//
//  PortfolioViewData.swift
//  portfolio_tracker
//
//  Thread-safe portfolio data for passing across actor boundaries
//

import Foundation

struct PortfolioViewData: Sendable, Identifiable {
    let id: UUID
    let name: String
    let totalValue: Double
    let riskProfile: RiskProfile
    let positionCount: Int
    let targetAllocation: [String: Double]?
    
    static func from(_ portfolio: Portfolio) -> PortfolioViewData {
        let positionSet = portfolio.positions as? Set<Position> ?? []
        return PortfolioViewData(
            id: portfolio.id ?? UUID(),
            name: portfolio.name ?? "Unnamed",
            totalValue: portfolio.totalValue,
            riskProfile: portfolio.riskProfile,
            positionCount: positionSet.count,
            targetAllocation: portfolio.targetAllocation
        )
    }
}
