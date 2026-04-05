# PortfolioTracker

macOS portfolio tracking application with AI-powered rebalancing advice.

## 🔐 Security Notice

**This repository is public. API keys and personal data are NEVER committed.**

- API keys are stored in **macOS Keychain** (secure, encrypted)
- Portfolio data stays on your **local device** only
- No data is sent to external servers except API calls

See [SECURITY.md](SECURITY.md) for details.

## Requirements

- macOS 14.0+
- Xcode 16.0+
- Swift 6.0
- Alpha Vantage API key (for US/HK stocks)
- Kimi API key or Baidu Qianfan API key (optional, for AI advisor)

**Note:** Chinese funds use 天天基金 API (free, no authentication required)

## Setup

### 1. Clone and Open

```bash
git clone https://github.com/xingran815/portfolio-tracker.git
cd portfolio-tracker
open portfolio_tracker.xcodeproj
```

### 2. Configure API Keys

**Alpha Vantage** (for stock prices):
1. Get free API key at [alphavantage.co/support/#api-key](https://www.alphavantage.co/support/#api-key)
2. In the app: Settings → API Keys → Alpha Vantage

**Kimi API** (optional, for AI advisor):
1. Get API key at [platform.moonshot.cn](https://platform.moonshot.cn)
2. In the app: Settings → API Keys → Kimi API

**Baidu Qianfan API** (optional, alternative AI advisor):
1. Get API key at [Qianfan Platform](https://qianfan.baidu.com)
2. In app: Settings → LLM Provider → Baidu Qianfan
3. Choose model: kimi-k2.5 (256k), glm-5 (198k), or minimax-m2.5 (192k)

**Chinese Funds** (no setup required):
- Uses 天天基金 API (free, no API key)
- Automatically fetches fund NAV

API keys are stored securely in macOS Keychain and never leave your device.

### 3. Build and Run

```bash
Cmd+R in Xcode
```

## Project Structure

```
portfolio_tracker/
├── Models/                         # CoreData entities
│   ├── Enums.swift                 # RiskProfile, AssetType, Market
│   ├── Portfolio+Extensions.swift  # Portfolio business logic
│   ├── Position+Extensions.swift   # Position business logic
│   └── Transaction+Extensions.swift # Transaction business logic
├── Services/                       # Business logic
│   ├── APIKeyManager.swift         # Secure keychain storage
│   ├── DataProvider/               # Price fetching (Phase 2)
│   ├── LLM/                        # Chat service (Phase 3)
│   └── Parser/                     # Markdown parser (Phase 4)
├── ViewModels/                     # SwiftUI view models (Phase 6)
├── Views/                          # SwiftUI views (Phase 6)
├── Utils/                          # Helper utilities
├── Persistence.swift               # CoreData controller
├── ContentView.swift               # Main view
└── portfolio_trackerApp.swift      # App entry
```

## Architecture

```
SwiftUI → ViewModels → Services → CoreData
                ↓
         APIKeyManager (Keychain)
                ↓
         ┌──────────────────────┐
         │ AlphaVantage API     │ (US/HK stocks)
         │ 天天基金 API          │ (Chinese funds)
         │ Exchange Rate API    │ (Currency conversion)
          │ Kimi API             │ (LLM advisor option 1)
          │ Baidu Qianfan API    │ (LLM advisor option 2)
         └──────────────────────┘
```

## Data Privacy

| Data Type | Storage | Encrypted |
|-----------|---------|-----------|
| API Keys | macOS Keychain | ✅ Yes |
| Portfolio Data | Local CoreData | ✅ FileVault |
| Cache | ~/Library/Caches | ❌ No (temporary) |
| Settings | UserDefaults | ❌ No |

## Phase Status

- [x] Phase 1: CoreData Models + Xcode Project
- [x] Phase 2: AlphaVantage Provider
- [x] Phase 3: LLM Service (Kimi API + Baidu Qianfan)
- [x] Phase 4: MD Parser
- [x] Phase 5: Rebalancing Engine
- [x] Phase 6: SwiftUI Views
- [x] Phase 7: Feature Enhancements
  - 天天基金集成
  - 快捷导入模式
  - 汇率换算
  - 数据同步优化
  - 现金类型支持

See [GitHub Issues](https://github.com/xingran815/portfolio-tracker/issues) for detailed phase breakdown.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am '[Phase X] Description'`
4. Push to branch: `git push origin feature/my-feature`
5. Create a Pull Request

**Note:** All PRs require:
- ✅ Build passes
- ✅ SwiftLint passes  
- ✅ 1 code review approval

## License

MIT License - See [LICENSE](LICENSE) file

## Disclaimer

This app is for educational purposes. Not financial advice. Always consult a professional financial advisor before making investment decisions.
