# Security Policy

## ⚠️ Pre-Production Software

**USE AT YOUR OWN RISK**: This SDK is in active development and has not been audited by external security professionals. Do not use in production with significant value.

## Supported Versions

| Version | Status |
| ------- | ------ |
| 0.2.x   | Current - Security hardened |
| 0.1.x   | Deprecated - upgrade to 0.2.0 |

## Recent Security Improvements (v0.2.0)

The SDK underwent comprehensive internal security review in January 2026:

- **3 Critical Fixes**: Authorization bypass, integer underflow, missing auth check
- **7 High Priority Fixes**: Race condition, time boundaries, quote expiry, info leakage, placeholder removal, state rollback patterns, HTTP outcall resilience
- **3 Code Quality Improvements**: Constants, event accuracy, parsing consolidation

**All critical and high-priority security issues identified in the review have been resolved.**

See [README Security Section](README.md#recent-security-improvements) for details.

## Reporting a Vulnerability

Found a security issue? Please report it responsibly.

**GitHub Security Advisories**: [Create Private Security Advisory](https://github.com/yourusername/icp-intents/security/advisories/new)

Or open a GitHub issue if not critical.

### What to Include

- Type of vulnerability
- Affected component
- Steps to reproduce
- Impact assessment
- Suggested fix (optional)

We'll respond within a few days and work with you on a fix.

## Known Limitations

This SDK has NOT undergone:

- [ ] External security audit
- [ ] Formal verification
- [ ] Large-scale load testing
- [ ] Chain reorg stress testing

## Security Best Practices

1. Use the latest version (0.2.x+)
2. Test thoroughly before any production use
3. Use solver allowlists
4. Monitor events for suspicious activity
5. Start with small amounts

---

**Last Updated**: January 2, 2026
