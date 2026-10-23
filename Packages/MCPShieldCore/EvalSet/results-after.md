Evaluated 36 configs, 69 servers.

| Rule | TP | FP | FN | Precision | Recall |
|---|---|---|---|---|---|
| CFG-001 | 9 | 2 | 5 | 82% | 64% |
| CFG-002 | 14 | 0 | 0 | 100% | 100% |
| CFG-003 | 3 | 0 | 1 | 100% | 75% |
| CFG-004 | 4 | 0 | 0 | 100% | 100% |
| CFG-005 | 3 | 0 | 1 | 100% | 75% |
| CFG-006 | 3 | 0 | 0 | 100% | 100% |
| SEC-001 | 9 | 0 | 2 | 100% | 82% |
| **All** | 45 | 2 | 9 | 96% | 83% |

Mistakes:
FP CFG-001 05-readme-slack-placeholder.json slack
FP CFG-001 13-non-secret-key-names.json llm-tools
FN CFG-001 14-database-url-password.json supabase
FN CFG-001 16-remote-headers.json github-remote
FN CFG-001 16-remote-headers.json internal-api
FN CFG-003 17-mcp-remote-proxy.json legacy
FN CFG-005 23-filesystem-docker.json filesystem
FN SEC-001 30-github-fine-grained-pat.json github
FN SEC-001 31-slack-real-token.json slack
FN CFG-001 32-secret-in-args.json openai-cli
FN CFG-001 35-kitchen-sink.json remote-bad
