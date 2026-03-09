# Kimi API Reference

## Working Configuration

```swift
// Endpoint
baseURL = "https://api.kimi.com/coding/v1"

// Required Headers
Authorization: "Bearer {API_KEY}"
User-Agent: "claude-code/2.0"
X-Client-Name: "claude-code"

// Model
"model": "kimi-latest"  // resolves to "kimi-for-coding"
```

## Key Implementation (KimiService.swift)

```swift
actor KimiService: LLMServiceProtocol {
    private let baseURL = "https://api.kimi.com/coding/v1"
    private let apiKeyManager: APIKeyManager
    
    func sendMessage(_ message: String, context: ConversationContext, history: [ChatMessage]) -> AsyncStream<String> {
        // 1. Get API key from Keychain
        // 2. Build request with headers
        // 3. Stream SSE response
    }
}
```

## Authentication Headers by Endpoint

| Endpoint | Authorization | User-Agent | X-Client-Name |
|----------|--------------|------------|---------------|
| `.kimiCoding` (default) | Bearer {key} | claude-code/2.0 | claude-code |
| `.moonshot` | Bearer {key} | - | - |
| `.custom` | Bearer + x-api-key | configurable | configurable |

## Request Format

```json
{
  "model": "kimi-latest",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "temperature": 0.7,
  "max_tokens": 2048,
  "stream": true
}
```

## Response Format (SSE)

```
data: {"choices":[{"delta":{"content":"Hello"}}]}
data: {"choices":[{"delta":{"content":"!"}}]}
data: [DONE]
```

## Storage Location

- **API Key**: macOS Keychain
- **Service**: `com.portfolio_tracker.apikeys`
- **Account**: `com.portfolio_tracker.kimi`

## Testing

```bash
# Test script
swift Scripts/test-kimi-final.swift

# Expected output
✅ HTTP Status: 200
✅ Model: kimi-for-coding
```

## Fallback

If no API key: Use `MockLLMService` for development
