# Pull Request Template

## 📋 Pull Request Checklist

Please check if your PR fulfills the following requirements:

- [ ] Tests for the changes have been added/updated (required for bug fixes/features)
- [ ] Documentation has been reviewed and updated if needed
- [ ] Build (`forge build`) succeeds locally
- [ ] Tests (`forge test`) pass locally
- [ ] Code formatting (`forge fmt --check`) passes
- [ ] Gas snapshots (`forge snapshot`) are updated if gas usage changed
- [ ] No new security warnings from `slither` or `forge coverage`

## 🎯 Pull Request Type

Please check the type of change your PR introduces:

- [ ] Bugfix (non-breaking change fixing an issue)
- [ ] Feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature that breaks existing functionality)
- [ ] Gas optimization (improves gas efficiency without changing logic)
- [ ] Documentation update only
- [ ] Code style/refactoring (no functional changes)
- [ ] Test improvement (adding/modifying tests)
- [ ] Security fix

## 🔗 Related Issue

**Issue Number:** # (e.g., #42)

**Relation:** 
- [ ] Fixes the issue
- [ ] Contributes to the issue
- [ ] Related to the issue

## 📝 Description

**What changes does this PR introduce?**

<!-- Describe your changes in detail -->

**Why are these changes necessary?**

<!-- Explain the motivation and context -->

**How does this PR solve the problem?**

<!-- Technical explanation of the solution -->

## 🧪 Testing

### Test Configuration

| Component | Version |
|-----------|---------|
| Foundry | `forge --version` |
| Solidity | `^0.8.20` |
| Network (if deployed) | Sepolia / Mainnet |

### Test Coverage

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated (if applicable)
- [ ] Fuzz tests added (for critical functions)

**Test Results:**

```bash
# Run this command and paste output
forge test -vvv
```

**Coverage Report:**

```bash
# Run this command and paste output
forge coverage
```

### Test Steps for Reviewer

1. 
2. 
3. 

## 📊 Gas Impact

| Function | Before (gas) | After (gas) | Change |
|----------|--------------|-------------|--------|
| `transfer` | | | |
| `delegate` | | | |
| `vote` | | | |

- [ ] Gas usage increased (explain why)
- [ ] Gas usage decreased
- [ ] No significant gas change

## 🔒 Security Considerations

- [ ] No reentrancy vulnerabilities introduced
- [ ] Access control properly implemented
- [ ] Input validation added for all external functions
- [ ] No unchecked blocks that could overflow
- [ ] Events emitted for all state changes
- [ ] Slither analysis passes

**Slither Output:**

```bash
# Run slither and paste relevant output
slither .
```

## 💥 Breaking Changes

Does this PR introduce breaking changes?

- [ ] Yes
- [ ] No

**If yes, please describe:**

| Changed Component | Old Behavior | New Behavior | Migration Path |
|------------------|--------------|--------------|----------------|
| | | | |

## 📚 Documentation Updates

- [ ] NatSpec comments added/updated for all public/external functions
- [ ] README.md updated (if applicable)
- [ ] Deployment instructions updated (if applicable)
- [ ] Examples added/updated (if applicable)

**Files updated:**

- `src/`
- `README.md`
- `docs/`

## 🧾 Commit Format

Please ensure commits follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type used in this PR:**
- [ ] `feat` - New feature
- [ ] `fix` - Bug fix
- [ ] `docs` - Documentation
- [ ] `style` - Code style/formatting
- [ ] `refactor` - Code refactoring
- [ ] `perf` - Gas/performance optimization
- [ ] `test` - Testing
- [ ] `chore` - Maintenance

**Example commit from this PR:**

```
feat(voting): add delegation timelock

Implement timelock mechanism for delegate changes
to prevent immediate voting power manipulation.

- Add TimelockController integration
- Emit DelegateScheduled event
- Update tests for timelock behavior

Gas impact: +500 gas for delegate() function
```

## 📦 Dependencies

**New dependencies added:**
```toml
# Add to foundry.toml or lib/
```

**Dependencies removed:**
```toml
```

**Dependencies updated:**
| Dependency | Old Version | New Version | Reason |
|------------|-------------|-------------|--------|
| forge-std | | | |

## 🌐 Deployment Information (if applicable)

**Network:** (e.g., Sepolia, Mainnet)

**Deployment Address:** `0x...`

**Verification:** 
- [ ] Verified on Etherscan
- [ ] Verification command: `forge verify-contract`

**Initial Parameters:**
```json
{
  "name": "",
  "symbol": "",
  "initialSupply": ""
}
```

## 📸 Evidence (if applicable)

**Screenshots/Logs:**

<!-- Attach relevant terminal output, test results, or verification screenshots -->

## ✅ PR Submission Checklist

**Before submitting, confirm:**

- [ ] I have read the [CONTRIBUTING.md](CONTRIBUTING.md) guide
- [ ] My PR title follows the Conventional Commits format
- [ ] My branch is rebased on the latest `main` branch
- [ ] I have resolved all merge conflicts
- [ ] All CI checks pass on my branch
- [ ] I have requested at least one reviewer

## 👀 Reviewer Focus

**Please pay special attention to:**

1. 
2. 
3. 

---

## 📌 Additional Context

<!-- Any other information that would help reviewers -->

---

**Thank you for contributing to Metarang Governance!** 🏛️

*For security issues, please email security@metarang.com instead of creating a PR.*

---

## 🏷️ Auto-label Suggestions

<!-- These will be automatically added by GitHub Actions -->
/label ~"needs review"
/cc @maintainers
```

**END OF PULL REQUEST TEMPLATE**
