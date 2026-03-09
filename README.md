# PortfolioTracker

macOS portfolio tracking application with AI-powered rebalancing advice.

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 6.0

## Project Structure

```
portfolio_tracker/
├── Models/
│   ├── Enums.swift               # RiskProfile, AssetType, Market, etc.
│   ├── Portfolio+Extensions.swift # Portfolio entity extensions
│   ├── Position+Extensions.swift  # Position entity extensions
│   └── Transaction+Extensions.swift # Transaction entity extensions
├── Utils/
│   └── Formatters.swift          # Currency/percentage formatters
├── Services/
│   ├── DataProvider/             # Price fetching (Phase 2)
│   ├── LLM/                      # Chat service (Phase 3)
│   └── Parser/                   # Markdown parser (Phase 4)
├── ViewModels/                   # SwiftUI view models (Phase 6)
├── Views/                        # SwiftUI views (Phase 6)
├── Persistence.swift             # CoreData controller
├── ContentView.swift             # Main view
└── portfolio_trackerApp.swift    # App entry
```

## Setup

1. Open `portfolio_tracker/portfolio_tracker.xcodeproj` in Xcode
2. Follow `MIGRATION_GUIDE.md` to configure CoreData model
3. Build and run (⌘+R)

## Architecture

```
SwiftUI → ViewModels → Services → CoreData
                ↓
         AlphaVantage API
                ↓
         Kimi API (LLM)
```

## Phase Status

- [x] Phase 1: CoreData Models + Xcode Project
- [ ] Phase 2: AlphaVantage Provider
- [ ] Phase 3: LLM Service
- [ ] Phase 4: MD Parser
- [ ] Phase 5: Rebalancing Engine
- [ ] Phase 6: SwiftUI Views
- [ ] Phase 7: Swift Testing
