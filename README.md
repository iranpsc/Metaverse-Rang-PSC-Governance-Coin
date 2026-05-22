# Metarang PSC Governance Coin

A decentralized governance token for the Metarang ecosystem, built with Foundry.

## Overview

This smart contract implements a standard governance token (ERC-20 based) that enables community-driven decision making within the Metarang platform.

## Features

- Voting Power - Token holders can vote on proposals
- Delegation - Delegate voting power to other addresses
- Proposal Creation - Submit new governance proposals
- Treasury Management - Participate in budget allocation decisions

## 🏦 Investor Vesting Contract (قرارداد قفل‌سازی سرمایه‌گذار)

این پروژه شامل یک قرارداد وستینگ پله‌ای (Step Vesting) برای سرمایه‌گذاران متارنگ است که توکن‌های آنها را در بازه‌های زمانی مشخص آزاد می‌کند.

### شرایط وستینگ

| آیتم | مقدار |
|------|-------|
| تعداد مراحل | 4 مرحله |
| مدت هر مرحله | 180 روز (حدود 6 ماه) |
| مدت کل | 720 روز (حدود 2 سال) |
| برنامه آزادسازی | 25% در هر مرحله |

### جدول آزادسازی توکن‌ها

| مرحله | زمان | درصد آزاد شده | وضعیت |
|-------|------|---------------|--------|
| 1 | روز صفر (همان ابتدا) | 25% | قابل برداشت فوری |
| 2 | پس از 180 روز | 25% | 50% کل |
| 3 | پس از 360 روز | 25% | 75% کل |
| 4 | پس از 540 روز | 25% | 100% کل |

### توابع اصلی قرارداد

| تابع | کاربرد |
|------|--------|
| releasable() | نمایش مقدار توکن‌های قابل برداشت در لحظه فعلی |
| release() | برداشت توکن‌های آزاد شده توسط سرمایه‌گذار |
| vestedAmount() | محاسبه مقدار کل توکن‌های آزاد شده تا یک تاریخ مشخص |

> نکته: قرارداد قابلیت دریافت کوین بومی شبکه (ETH) را نیز دارد.

## Technical Stack

- Solidity ^0.8.20
- Foundry (Forge, Cast, Anvil)
- EVM-compatible chains (Ethereum, Polygon, BSC)

## Quick Start

```bash
# Clone the repository
git clone https://github.com/iranpsc/metarang-PSC-governance-coin.git

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test


