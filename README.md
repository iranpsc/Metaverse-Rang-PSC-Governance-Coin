🪙 PSC Token — Paradaise Supply Chain

A Sustainable ERC‑20 Token with Annual Release Algorithm & Smart Vesting
https://img.shields.io/badge/License-GPL%2520v3-blue.svg
https://img.shields.io/badge/Solidity-0.8.20-black
https://img.shields.io/badge/OpenZeppelin-v5.0-blue
https://img.shields.io/badge/Hardhat-Ready-brightgreen
https://img.shields.io/badge/Remix-Compatible-orange
https://img.shields.io/badge/Code%2520Style-Prettier-ff69b4
https://img.shields.io/badge/Gas-Optimized-success


📌 Overview
PSC (Paradaise Supply Chain) is a production‑ready ERC‑20 token built for modern supply chain ecosystems. Unlike traditional token models with static vesting schedules, PSC implements a sustainable annual release algorithm that ensures long‑term stability, gradual liquidity, and aligned incentives for all stakeholders.

The contract is fully self‑contained — all wallet addresses and allocations are hardcoded on‑chain, making deployment a one‑click process with zero configuration overhead.


✨ Key Features
Feature	Description
🔄 Annual Release Algorithm	10% of remaining supply is released every year, ensuring long‑term sustainability
👥 57 Team Members	Custom allocations per member (non‑uniform), fully transparent on‑chain
🎁 Smart Airdrop	60‑day cliff + 1‑year linear vesting to prevent instant dumps
🏦 Developer Wallet	Receives 1% annually from year 2 onward (controlled by the owner)
🛡️ Enterprise‑Grade Security	Pausable, ReentrancyGuard, SafeERC20, and Ownable
⚡ Gas Optimized	Carefully tuned loops and unchecked blocks for minimal deployment cost
🔍 Full Transparency	Team names, addresses, and allocations are permanently stored on‑chain
📦 One‑Click Deploy	All addresses are hardcoded — just deploy and go!


🧱 Tokenomics
📊 Total Supply & Distribution
Parameter	Value
Token Name	Paradaise Supply Chain
Symbol	PSC
Total Supply	200,000,000 PSC
Decimals	18
Release Start Date	August 23, 2027 (Shahrivar 1406)
Annual Release	10% of remaining supply


📋 Year 1 — Initial Distribution (10% of Total Supply)
When the contract is deployed, the first 10% (20,000,000 PSC) is automatically distributed:

Category	Percentage	Amount (PSC)	Recipient
Team Members	1%	2,000,000	57 wallets (custom amounts)
Founders	5%	10,000,000	Hossein Ghadiri (5M) & Amir Madani Far (5M)
Airdrop	2%	4,000,000	Locked with 60‑day cliff + 1‑year vesting
Uniswap Initial Offering	2%	4,000,000	Hossein Ghadiri's wallet (for liquidity)


📆 Annual Releases (Year 2 and Beyond)
From year 2 onward, the owner calls releaseAnnual() once every 365 days to release 10% of the remaining supply:

Category	Percentage (of remaining supply)	Recipient
Developer Wallet	1%	0xb0E70A61D6395398c1AE9C417d2604418417e414
Founders	5%	Hossein Ghadiri (2.5%) & Amir Madani Far (2.5%)
Public Distribution	4%	Hossein Ghadiri's wallet (for Uniswap liquidity)
💡 Why "remaining supply"? This model ensures the token never experiences sudden inflation spikes. As the supply decreases over time, the absolute amount released each year gradually shrinks, creating a natural deflationary pressure.



👥 Team Members — Full On‑Chain Disclosure
All 57 team members are hardcoded in the contract with their exact allocations. Below is a sample:

#	Name	Role	Allocation (PSC)
1	Abbas Ajorlo	Development Lead	52,390.54555
2	Ali Khani	Development	40,013.94255
3	Ramtin Golben	Backend	14,262.09495
4	Mohammad Amir Kheradmand	Backend	14,232.24058
5	Mahan Jamali	Backend	14,033.21146
...	...	...	...
55	Parsa Abolhasani Rad	Blockchain Developer	33,083.61530
56	Mohammad Ghiasvand	Blockchain Developer	24,603.03982
57	Ali Nasirloo	Blockchain Developer	31,251.16525
🔍 Anyone can verify by calling getTeamMembers() and getTeamAllocation(address) on the contract.


🎁 Airdrop Mechanism — Smart Vesting
The airdrop is designed to prevent instant selling pressure and reward long‑term believers.

📐 Parameters
Parameter	Value
Total Airdrop Pool	4,000,000 PSC (2% of total supply)
Max Recipients	1,000 users
Cliff (Lock Period)	60 days (no withdrawals)
Vesting Duration	1 year (365 days) after cliff
Release Schedule	Linear (daily)


📈 How It Works
Day 1 — Airdrop is distributed (tokens are locked in the contract).
Day 1–60 — Recipients cannot withdraw anything (Cliff period).
Day 61 — Vesting begins. Tokens unlock linearly every day.
Day 61–425 — Recipients can claim their vested tokens at any time.
Day 426+ — All tokens are fully claimable


🧮 Formula
Elapsed = block.timestamp - vestingStartTime

IF Elapsed < 60 days → 0 claimable
IF Elapsed >= 60 + 365 days → full allocation claimable
ELSE:
    vestingElapsed = Elapsed - 60 days
    vestedPercentage = vestingElapsed / 365 days
    claimable = totalAllocation × vestedPercentage − alreadyClaimed



    💻 User Actions
Step	Action
1	Owner calls distributeAirdrop(address[]) with list of recipients
2	Recipients wait 60 days
3	Recipients call claimAirdrop() to withdraw vested tokens
4	(Optional) Check status via getClaimableAmount(address)


🛡️ Security Features
Feature	Description
ReentrancyGuard	Protects against re‑entrancy attacks on all sensitive functions
Pausable	Emergency stop for all transfers (only owner)
SafeERC20	Safe token transfers with return value checks
Ownable	Access control — sensitive functions are onlyOwner
Rescue Tokens	Owner can recover accidentally sent tokens (but cannot touch locked tokens)
Input Validation	All addresses are validated against address(0)
Total Supply Validation	Automatic check that team allocation equals exactly 1% of total supply


🛠️ Technology Stack
Layer	Technology
Smart Contract	Solidity ^0.8.20
Libraries	OpenZeppelin Contracts v5.0
Testing	Hardhat / Foundry
Deployment	Hardhat / Remix IDE
Security Analysis	Slither, MythX (recommended)
Wallet Support	MetaMask, WalletConnect, any Web3 wallet


🚀 Deployment Guide
Prerequisites
Node.js (v18+)

npm or yarn

MetaMask (or any Web3 wallet)

Quick Start with Remix
Open Remix IDE
Create a new file: PSC.sol
Paste the contract code
Compile with Solidity 0.8.20
Set Gas Limit to 5,000,000
Click Deploy (no parameters needed!)
Confirm transaction in your wallet


Hardhat Deployment
# Clone the repository
git clone https://github.com/yourusername/psc-token.git
cd psc-token
# Install dependencies
npm install
# Compile
npx hardhat compile
# Deploy to Sepolia
npx hardhat run scripts/deploy.js --network sepolia
# Deploy to Mainnet
npx hardhat run scripts/deploy.js --network mainnet


Deployment Script (scripts/deploy.js)
const hre = require("hardhat");

async function main() {
  const PSC = await hre.ethers.getContractFactory("PSC");
  const psc = await PSC.deploy();
  await psc.waitForDeployment();

  console.log("PSC deployed to:", await psc.getAddress());
}

main().catch(console.error);

🔍 Contract Functions
Admin Functions (onlyOwner)
Function	Description
pause()	Pause all transfers (emergency)
unpause()	Resume transfers
releaseAnnual()	Release 10% of remaining supply (once per year)
setDeveloperWallet(address)	Update developer wallet address
setFounderWallets(address, address)	Update founder addresses
setPublicWallets(address, address)	Update public offering & distribution wallets
distributeAirdrop(address[])	Distribute airdrop to up to 1000 users (one‑time)


View Functions (Public)
Function	Description
getRemainingSupply()	Total supply still locked in the contract
getTimeUntilNextRelease()	Seconds remaining until next annual release
getCirculatingSupply()	Total supply minus locked tokens
getTeamMembers()	Array of all 57 team member addresses
getTeamMembersCount()	Number of team members (57)
getTeamAllocation(address)	Token allocation for a specific team member
getAirdropInfo(address)	Vesting info: total, claimed, start time
getAirdropRecipientsCount()	Number of airdrop recipients
canClaimAirdrop(address)	Check if a user can claim
getClaimableAmount(address)	Amount currently available to claim
getAirdropAmountPerRecipient(uint256)	Amount per recipient for a given count


User Functions
Function	Description
claimAirdrop()	Claim vested airdrop tokens


📄 Contract Verification (Etherscan)
Because all addresses are hardcoded, verification is super simple:
# Verify on Sepolia
npx hardhat verify --network sepolia DEPLOYED_CONTRACT_ADDRESS

# Verify on Mainnet
npx hardhat verify --network mainnet DEPLOYED_CONTRACT_ADDRESS


📂 Project Structure
psc-token/
├── contracts/
│   └── PSC.sol              # Main contract (fully self‑contained)
├── scripts/
│   ├── deploy.js            # Deployment script
│   └── verify.js            # Verification script
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

# Run specific test file
npx hardhat test test/PSC.test.js


📊 Technical Specifications
Parameter	Value
Token Name	Paradaise Supply Chain
Symbol	PSC
Total Supply	200,000,000 (with 18 decimals)
Solidity Version	0.8.20
Recommended Network	Sepolia (test) / Ethereum Mainnet
Estimated Gas (Deploy)	~4,500,000 – 5,500,000
Max Airdrop Recipients	1,000
Airdrop Cliff	60 days
Airdrop Vesting	365 days
Annual Release	10% of remaining supply


👨‍💻 Core Team
Name	Role
Hossein Ghadiri	Founder — Concept Creator
Amir Madani Far	Founder — Concept Creator
Abbas Ajorlo	Development Lead
Parsa Abolhasani Rad	Blockchain Developer
Ali Nasirloo	Blockchain Developer
Mohammad Ghiasvand	Blockchain Developer
👥 Full list of 57 team members is available on‑chain via getTeamMembers().


🤝 Contributing
We welcome contributions from the community!
Fork the repository
Create a feature branch (git checkout -b feature/amazing)
Commit your changes (git commit -m 'Add amazing feature')
Push to the branch (git push origin feature/amazing)
Open a Pull Request


Code Style
Follow Solidity best practices
Use unchecked for gas optimization where safe
Write tests for new features
Update documentation

📄 License
This project is licensed under the GPL-3.0 License — see the LICENSE file for details.

🌐 Links & Resources
Solidity Documentation
OpenZeppelin Documentation
Sepolia Etherscan
Uniswap
Etherscan
Hardhat Documentation


⭐ Show Your Support
If this project has been helpful to you, please give it a ⭐ on GitHub!


Last Updated: August 2026
