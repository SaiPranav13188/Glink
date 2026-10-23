Evaluated 36 configs, 69 servers.

| Rule | TP | FP | FN | Precision | Recall |
|---|---|---|---|---|---|
| CFG-001 | 9 | 2 | 5 | 82% | 64% |
| CFG-002 | 10 | 6 | 4 | 62% | 71% |
| CFG-003 | 3 | 0 | 1 | 100% | 75% |
| CFG-004 | 4 | 0 | 0 | 100% | 100% |
| CFG-005 | 3 | 0 | 1 | 100% | 75% |
| CFG-006 | 3 | 0 | 0 | 100% | 100% |
| SEC-001 | 9 | 0 | 2 | 100% | 82% |
| **All** | 41 | 8 | 13 | 84% | 76% |

Mistakes:
FP CFG-001 05-readme-slack-placeholder.json slack
FP CFG-002 09-leaked-llm-keys.json anthropic-proxy
FP CFG-001 13-non-secret-key-names.json llm-tools
FN CFG-001 14-database-url-password.json supabase
FN CFG-001 16-remote-headers.json github-remote
FN CFG-001 16-remote-headers.json internal-api
FN CFG-003 17-mcp-remote-proxy.json legacy
FN CFG-005 23-filesystem-docker.json filesystem
FP CFG-002 24-git-home-pinned.json git
FP CFG-002 25-pinned-variants.json npx-package-flag
FP CFG-002 25-pinned-variants.json pipx-pin
FP CFG-002 25-pinned-variants.json uvx-from-pin
FN CFG-002 26-unpinned-variants.json bunx-plain
FN CFG-002 26-unpinned-variants.json caret-range
FN CFG-002 26-unpinned-variants.json tilde-range
FN SEC-001 30-github-fine-grained-pat.json github
FN SEC-001 31-slack-real-token.json slack
FN CFG-001 32-secret-in-args.json openai-cli
FP CFG-002 34-vscode-servers-key.json sqlite
FN CFG-002 35-kitchen-sink.json bad-everything
FN CFG-001 35-kitchen-sink.json remote-bad
