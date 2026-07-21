# 🪙 Paradaise Supply Chain Token (PSC)

### ERC-20 Token with Transparent Team Vesting & Investor Step Vesting

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.27-black)](https://soliditylang.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5.0-blue)](https://openzeppelin.com/)
[![Hardhat](https://img.shields.io/badge/Hardhat-Ready-brightgreen)](https://hardhat.org/)
[![Code Style](https://img.shields.io/badge/Code%20Style-Prettier-ff69b4)](https://prettier.io/)

---

## 📌 Overview

**PSC (Paradaise Supply Chain)** is a production‑ready ERC‑20 token designed for supply chain ecosystems. The contract includes:

- ✅ **Standard ERC-20 functionality** with burn and mint capabilities (via `Ownable`)
- ✅ **Linear vesting** for team members (1-year cliff + 2-year linear release)
- ✅ **Step vesting** for investors (4 steps of 6 months each)
- ✅ **Transparent team disclosure** — names and addresses are stored on‑chain
- ✅ **Security features**: `Pausable`, `ReentrancyGuard`, `SafeERC20`
- ✅ **Emergency rescue** for accidentally sent tokens

---

## 🧱 Tokenomics

| Category | Percentage | Amount (PSC) | Release Mechanism |
|----------|------------|--------------|-------------------|
| **Public Sale** | 10% | 2,000,000 | Unlocked at TGE |
| **Team** | 3% | 600,000 | 1-year cliff + 2-year linear vesting |
| **Investor** | 87% | 17,400,000 | 4-step vesting (6 months each) |
| **Total** | **100%** | **20,000,000** | — |

---

## 👥 Team Members (On‑Chain Disclosure)

| # | Name | Role |
|---|------|------|
| 1 | **Hosein Ghadiri** | Project Owner |
| 2 | **Amir Madani Far** | Project Owner |
| 3 | ** Abbas Ajorlo** | Backend Developer |
| 4 | **Parsa Abolhasani Rad** | Blockchain Developer |

> 🔍 Anyone can verify team members by calling `getTeamMembers()` on the contract.

---

## 🕒 Vesting Mechanisms

### Team Vesting (Linear)

| Parameter | Value |
|-----------|-------|
| **Cliff** | 1 year (365 days) |
| **Vesting Duration** | 2 years (730 days) |
| **Total Team Allocation** | 600,000 PSC |
| **Per Member** | 150,000 PSC |

### Investor Vesting (Step)

| Parameter | Value |
|-----------|-------|
| **Start** | Configurable (future timestamp) |
| **Step Duration** | 6 months (180 days) |
| **Number of Steps** | 4 |
| **Total Investor Allocation** | 17,400,000 PSC |

**Release Schedule:**

- **Step 1 (Month 6):** 25% unlocked
- **Step 2 (Month 12):** 50% unlocked
- **Step 3 (Month 18):** 75% unlocked
- **Step 4 (Month 24):** 100% unlocked

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|------------|
| **Smart Contract** | Solidity 0.8.27 |
| **Libraries** | OpenZeppelin Contracts v5.0 |
| **Testing** | Hardhat / Foundry (recommended) |
| **Deployment** | Hardhat Deploy / Remix |
| **Security** | Slither, MythX (recommended) |

---

## 🚀 Quick Start

### Prerequisites

- Node.js (v18+)
- npm or yarn
- Hardhat (optional)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/psc-token.git
cd psc-token

# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test


🔍 Contract Functions
Core Functions
Function	Description
transfer(address to, uint256 amount)	Send tokens (pausable)
transferFrom(address from, address to, uint256 amount)	Send tokens on behalf (pausable)
pause()	Pause all transfers (onlyOwner)
unpause()	Resume transfers (onlyOwner)


Vesting Functions
Function	Description
teamVestingsCount()	Number of team vesting contracts
getTeamVestings()	List of team vesting contract addresses
getTeamMembers()	List of team member names and addresses
getTotalLockedTokens()	Total tokens still locked in all vesting contracts
getCirculatingSupply()	Total supply minus locked tokens


Investor Step Vesting
Function	Description
releasable(address token)	Tokens available to release
release(address token)	Release available tokens
revoke(address token, address to)	Revoke remaining tokens (beneficiary only)
getCurrentStep()	Current vesting step (0–4)
getVestedPercentage()	Percentage of tokens already vested


🛡️ Security Features
Feature	Description
ReentrancyGuard	Protects against reentrancy attacks
Pausable	Emergency stop for transfers
SafeERC20	Safe token transfers with error handling
Ownable	Restricted access to sensitive functions
Rescue Tokens	Recover accidentally sent tokens


📊 Contract Verification (Etherscan)
After deployment, verify your contract on Etherscan:
npx hardhat verify --network mainnet DEPLOYED_CONTRACT_ADDRESS \
  "0xpublicWallet" \
  ["0xteam1","0xteam2","0xteam3","0xteam4"] \
  ["Hosein Ghadiri","Amir Madani Far","Ajorlo","Parsa Abolhasani Rad"] \
  "0xinvestorWallet" \
  1735689600

📂 Project Structure
psc-token/
├── contracts/
│   └── PSC.sol              # Main contract (MyToken + InvestorStepVesting)
├── scripts/
│   └── deploy.js            # Deployment script
├── test/
│   └── PSC.test.js          # Unit tests
├── hardhat.config.js
├── package.json
└── README.md


🧪 Testing
# Run all tests
npx hardhat test

# Run with gas report
npx hardhat test --gas

# Run coverage
npx hardhat coverage

🤝 Contributing
Contributions are welcome! Please follow these steps:

1.Fork the repository
2.Create a feature branch (git checkout -b feature/amazing)
3.Commit your changes (git commit -m 'Add amazing feature')
4.Push to the branch (git push origin feature/amazing)
5.Open a Pull Request


📄 License
This project is licensed under the GPL-3.0 License — see the LICENSE file for details.

👨‍💻 Author
Hosein Ghadiri — Project Owner
Amir Madani Far — Project Owner
Ajorlo — Backend Developer
Parsa Abolhasani Rad — Blockchain Developer

⭐ Show Your Support
If you find this project useful, please give it a ⭐ on GitHub!

