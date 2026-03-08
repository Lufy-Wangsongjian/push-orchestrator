#!/usr/bin/env bash
# push-orchestrator provider: market-news (summary layer)
# Returns JSON: summary, source_links[]; for use with market-brief.
set -e
jq -n '{summary: "No news source configured.", source_links: []}'