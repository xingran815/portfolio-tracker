#!/bin/bash
#
# Setup API Keys for Local Development
# 
# This script reads API keys from .env.local and stores them in macOS Keychain
# Run this after cloning the repo to set up your development environment
#
# Usage: ./Scripts/setup-api-keys.sh
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env.local"

echo "🔐 PortfolioTracker API Key Setup"
echo "=================================="
echo ""

# Check if .env.local exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env.local not found!"
    echo ""
    echo "Please create .env.local with your API keys:"
    echo "  ALPHAVANTAGE_API_KEY=your_actual_key_here"
    echo ""
    exit 1
fi

# Source the .env.local file
source "$ENV_FILE"

# Function to store key in Keychain
store_key() {
    local service=$1
    local key=$2
    local account=$3
    
    if [ -z "$key" ] || [ "$key" = "your_key_here" ]; then
        echo "⚠️  Skipping $service (key not set)"
        return
    fi
    
    # Delete existing key if present
    security delete-generic-password -s "$service" -a "$account" 2>/dev/null || true
    
    # Add new key
    security add-generic-password \
        -s "$service" \
        -a "$account" \
        -w "$key" \
        -U \
        -T "" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ $service API key stored in Keychain"
    else
        echo "❌ Failed to store $service API key"
    fi
}

# Store Alpha Vantage key
if [ -n "$ALPHAVANTAGE_API_KEY" ] && [ "$ALPHAVANTAGE_API_KEY" != "your_key_here" ]; then
    store_key "com.portfolio_tracker.apikeys" "$ALPHAVANTAGE_API_KEY" "com.portfolio_tracker.alphavantage"
else
    echo "⚠️  ALPHAVANTAGE_API_KEY not set in .env.local"
fi

# Store Kimi key
if [ -n "$KIMI_API_KEY" ] && [ "$KIMI_API_KEY" != "your_key_here" ]; then
    store_key "com.portfolio_tracker.apikeys" "$KIMI_API_KEY" "com.portfolio_tracker.kimi"
else
    echo "⚠️  KIMI_API_KEY not set in .env.local (optional)"
fi

# Store Baidu Qianfan key
if [ -n "$BAIDUQIANFAN_API_KEY" ] && [ "$BAIDUQIANFAN_API_KEY" != "your_key_here" ]; then
    store_key "com.portfolio_tracker.apikeys" "$BAIDUQIANFAN_API_KEY" "com.portfolio_tracker.baiduqianfan"
else
    echo "⚠️  BAIDUQIANFAN_API_KEY not set in .env.local (optional)"
fi

# Store Tavily key
if [ -n "$TAVILY_API_KEY" ] && [ "$TAVILY_API_KEY" != "your_key_here" ]; then
    store_key "com.portfolio_tracker.apikeys" "$TAVILY_API_KEY" "com.portfolio_tracker.tavily"
else
    echo "⚠️  TAVILY_API_KEY not set in .env.local (optional, for web search)"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "You can now run the app. API keys are securely stored in Keychain."
