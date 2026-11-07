## Unreleased

- `Redaction`: masks secrets in headers, query and fragment parameters, form bodies and JSON bodies at any depth before anything is stored, by normalized name. `Redaction.standard`, `extend` (which can't remove a default), `withHeaders` for a client's `defaultHeaders`, a 64 KB cap, binary bodies as type and size, and `Redaction.maskSecret` for the Secure Store page.

## 0.1.0-dev.1

- S0: package skeleton.
