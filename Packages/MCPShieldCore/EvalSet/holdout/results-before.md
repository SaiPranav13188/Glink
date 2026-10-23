Evaluated 16 configs, 21 servers.

| Rule | TP | FP | FN | Precision | Recall |
|---|---|---|---|---|---|
| CFG-001 | 1 | 2 | 6 | 33% | 14% |
| CFG-002 | 0 | 0 | 0 | n/a | n/a |
| CFG-003 | 0 | 0 | 1 | n/a | 0% |
| CFG-004 | 0 | 0 | 0 | n/a | n/a |
| CFG-005 | 0 | 0 | 1 | n/a | 0% |
| CFG-006 | 0 | 0 | 0 | n/a | n/a |
| SEC-001 | 2 | 1 | 2 | 67% | 50% |
| **All** | 3 | 3 | 10 | 50% | 23% |

Mistakes:
FN CFG-001 h02-api-key-header.json search
FN CFG-001 h03-mongo-uri.json mongodb
FN SEC-001 h06-slack-user-token.json slack-user
FN CFG-001 h07-token-flag-equals.json gh-tools
FP CFG-001 h08-key-file-paths.json gcp
FN CFG-005 h09-docker-volume-root.json files-root
FN CFG-003 h10-supergateway-http.json gateway
FN CFG-001 h11-url-token-query.json zapier
FN CFG-001 h13-anthropic-in-header.json claude-relay
FN CFG-001 h14-docker-env-assignment.json github
FN SEC-001 h14-docker-env-assignment.json github
FP CFG-001 h15-placeholder-variety.json openai
FP SEC-001 h15-placeholder-variety.json openai
