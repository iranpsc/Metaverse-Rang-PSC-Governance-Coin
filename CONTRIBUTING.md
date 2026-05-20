# Contributing to Metarang PSC Governance Coin

Thank you for your interest in contributing to the Metarang Governance Coin! This smart contract is the backbone of decentralized governance in the Metarang ecosystem.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Enhancements](#suggesting-enhancements)
  - [Pull Requests](#pull-requests)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
  - [Solidity Standards](#solidity-standards)
  - [Foundry Standards](#foundry-standards)
  - [Commit Guidelines](#commit-guidelines)
- [Testing Requirements](#testing-requirements)
- [Security](#security)
- [Documentation](#documentation)

---

## Code of Conduct

This project and everyone participating in it is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

---

## Getting Started

### Prerequisites

- **Git**
- **Foundry** ([Installation Guide](https://book.getfoundry.sh/getting-started/installation))
- Basic knowledge of **Solidity** and **ERC-20/ERC-1155** standards

### Setup Development Environment

```bash
# 1. Fork the repository
# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/metarang-PSC-governance-coin.git
cd metarang-PSC-governance-coin

# 3. Install dependencies
forge install

# 4. Build the contracts
forge build

# 5. Run tests
forge test

# 6. (Optional) Run local node
anvil
```

---

## How Can I Contribute?

### Reporting Bugs

**Before creating a bug report**, please check existing issues to avoid duplicates.

**Bug Report Template:**

```markdown
**Title:** Brief summary of the issue

**Description:** Detailed description of the problem

**Steps to Reproduce:**
1. Call function `transfer` with parameter X
2. Error Y appears

**Expected Behavior:** Token should transfer successfully

**Environment:**
- Network: Ethereum Mainnet / Sepolia
- Wallet: MetaMask / Rabby
- Foundry Version: (output of `forge --version`)

**Additional Context:** Add any relevant code or transaction hashes
```

### Suggesting Enhancements

To suggest a new feature (e.g., adding `voteDelegation` capability):

1. Open an issue with label **`enhancement`**
2. Explain the feature and its use case
3. Provide example scenarios or pseudo-code if possible

**Enhancement Template:**

```markdown
**Title:** Clear description of the proposed feature

**Problem Statement:** What problem does this solve?

**Proposed Solution:** How should it work?

**Alternatives Considered:** Any other approaches?

**Additional Context:** Diagrams, references, or examples
```

### Pull Requests

#### Step-by-Step Process

1. **Create an issue first** - Discuss the change before implementing
2. **Assign yourself** to the issue
3. **Create a branch** from `main`:

```bash
git checkout -b feature/governance-timelock
# or
git checkout -b fix/transfer-bug
```

4. **Make your changes** following coding standards
5. **Write/update tests** for your changes
6. **Run tests locally**:

```bash
forge test
forge coverage
```

7. **Format your code**:

```bash
forge fmt
```

8. **Commit your changes** (follow commit guidelines)
9. **Push and create Pull Request**

#### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] All tests pass (`forge test`)

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review performed
- [ ] Comments added for complex logic
- [ ] Documentation updated
- [ ] No new warnings or vulnerabilities

## Related Issue
Fixes # (issue number)
```

---

## Development Setup

### Project Structure

```
metarang-PSC-governance-coin/
├── src/                 # Smart contract source files
├── test/                # Forge tests (Solidity)
├── script/              # Deployment scripts
├── lib/                 # Dependencies (forge-std, etc.)
├── foundry.toml         # Foundry configuration
└── .github/             # Issue/PR templates
```

### Common Commands

| Command | Description |
|---------|-------------|
| `forge build` | Compile contracts |
| `forge test` | Run all tests |
| `forge test -vvv` | Run tests with verbose output |
| `forge coverage` | Generate test coverage report |
| `forge fmt` | Format Solidity code |
| `forge snapshot` | Generate gas snapshots |
| `anvil` | Run local Ethereum node |
| `cast <subcommand>` | Interact with contracts |

---

## Coding Standards

### Solidity Standards

We follow **Solium** and **NatSpec** standards:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MetarangGovernanceCoin
 * @dev Governance token for Metarang ecosystem
 * @notice Holders can vote on proposals
 */
contract MetarangGovernanceCoin is ERC20 {
    
    /// @notice Maximum supply of the token
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18;
    
    /// @dev Emitted when a delegate is set
    event DelegateSet(address indexed account, address indexed delegate);
    
    /**
     * @dev Constructor sets token name and symbol
     * @param initialSupply Initial token supply
     */
    constructor(uint256 initialSupply) ERC20("Metarang Governance", "PSC") {
        _mint(msg.sender, initialSupply);
    }
    
    /**
     * @notice Delegate voting power to another address
     * @param delegatee Address to delegate to
     */
    function delegate(address delegatee) external {
        require(delegatee != address(0), "Invalid delegate");
        // Implementation...
        emit DelegateSet(msg.sender, delegatee);
    }
}
```

**Key Rules:**

- Use **SPDX-License-Identifier** at top
- Specify Solidity version (`^0.8.20`)
- Use **NatSpec** comments (`///` or `/** */`) for all public functions
- Follow **Checks-Effects-Interactions** pattern
- Use `require()` with error messages (or custom errors in newer versions)
- Name conventions: `camelCase` for functions, `UPPER_SNAKE_CASE` for constants
- Maximum line length: 120 characters

### Foundry Standards

**Test File Example:**

```solidity
// test/Governance.t.sol
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MetarangGovernanceCoin.sol";

contract GovernanceTest is Test {
    MetarangGovernanceCoin public token;
    address public owner = address(0x123);
    address public user = address(0x456);
    
    function setUp() public {
        vm.prank(owner);
        token = new MetarangGovernanceCoin(1_000_000 * 10**18);
    }
    
    function testTransfer() public {
        vm.prank(owner);
        token.transfer(user, 100 * 10**18);
        
        assertEq(token.balanceOf(user), 100 * 10**18);
    }
    
    function testCannotTransferMoreThanBalance() public {
        vm.prank(user);
        vm.expectRevert("ERC20: insufficient allowance");
        token.transfer(owner, 1_000_000 * 10**18);
    }
}
```

**Test Requirements:**

- Each feature must have corresponding tests
- Edge cases must be tested (zero addresses, overflow, etc.)
- Maintain minimum **80% test coverage**
- Use `vm.prank()` and `vm.expectRevert()` for access control tests
- Use `vm.assume()` for fuzz testing

### Commit Guidelines

We follow **Conventional Commits** specification:

**Format:**

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(voting): add delegation mechanism` |
| `fix` | Bug fix | `fix(transfer): prevent zero address transfers` |
| `docs` | Documentation | `docs: update README with deployment guide` |
| `style` | Code formatting | `style: run forge fmt` |
| `refactor` | Code restructuring | `refactor: extract validation to modifier` |
| `test` | Add/update tests | `test: add delegation edge cases` |
| `perf` | Gas optimization | `perf: reduce storage reads` |
| `chore` | Maintenance | `chore: update foundry.toml` |

**Examples:**

```bash
git commit -m "feat(voting): add timelock for proposal execution"
git commit -m "fix(mint): prevent exceeding max supply"
git commit -m "gas: optimize delegate function by caching storage"
```

---

## Testing Requirements

### Run Tests

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test file
forge test --match-path test/Governance.t.sol

# Run with coverage
forge coverage
```

### Test Coverage Goals

- **Critical paths** (transfers, minting, burning): 100%
- **Access control** (onlyOwner, onlyRole): 100%
- **Edge cases** (zero address, overflow): 100%
- **Overall coverage**: ≥ 80%

### Continuous Integration

Pull requests must pass all CI checks:

- [ ] `forge build` succeeds
- [ ] `forge test` passes
- [ ] `forge coverage` meets minimum threshold
- [ ] `forge fmt --check` passes
- [ ] No security warnings from `slither` or `mythril`

---

## Security

### Critical Considerations

This is a **governance token** - security is paramount. All changes must consider:

- **Reentrancy attacks** - Use Checks-Effects-Interactions pattern
- **Front-running** - Consider commit-reveal for voting
- **Flash loan attacks** - Use timelocks for critical operations
- **Access control** - Ensure only authorized addresses can mint/pause

### Reporting Security Vulnerabilities

**Do NOT open public issues for security vulnerabilities.** 

Email security concerns to: **security@metarang.com** (use PGP encryption if available)

We will respond within 48 hours and coordinate a responsible disclosure.

### Audit Requirement

Any significant changes to token economics or governance logic **must** be audited by a third-party security firm before merging.

---

## Documentation

### In-code Documentation

- Use **NatSpec** for all public/ external functions
- Document all state variables
- Add inline comments for complex logic

```solidity
/**
 * @notice Transfer tokens with delegation check
 * @dev Overrides ERC20 transfer to update delegate voting power
 * @param to Recipient address
 * @param amount Amount to transfer
 * @return bool Success status
 */
function transfer(address to, uint256 amount) public override returns (bool) {
    // Update delegate voting power before transfer
    _updateVotingPower(msg.sender, to, amount);
    return super.transfer(to, amount);
}
```

### README Updates

When adding features, update the [README.md](README.md) with:

- New functions and their purposes
- Deployment instructions (if changed)
- Interaction examples (using `cast`)
- Gas costs for major operations

---

## Questions or Need Help?

- **GitHub Issues**: For bug reports and feature requests
- **Discord**: Join our [Discord server](https://discord.gg/metarang)
- **Foundry Book**: [https://book.getfoundry.sh/](https://book.getfoundry.sh/)

---

## Recognition

Contributors will be:

- Added to the project's `CONTRIBUTORS.md` file
- Acknowledged in release notes
- Featured in project documentation (with permission)

---

**Thank you for contributing to decentralized governance!** 🏛️

*Happy building with Foundry!* 🔨
```

**END OF CONTRIBUTING GUIDE**
