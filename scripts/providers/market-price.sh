#!/usr/bin/env bash
# push-orchestrator provider: market-price (ground-truth layer)
# Returns JSON: price, change, source_url, data_timestamp; or error DATA_UNAVAILABLE.
set -e
# Stub: no real API. In production would fetch from trusted source.
# Output format for downstream market-brief.
jq -n \
  --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  '{
    price: null,
    change: null,
    source_url: "",
    data_timestamp: $ts,
    available: false,
    error: "DATA_UNAVAILABLE"
  }'
