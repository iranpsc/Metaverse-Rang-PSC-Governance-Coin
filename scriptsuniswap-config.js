// ============================================================
// UNISWAP V3 CONFIGURATION — PSC/USDT
// ============================================================

module.exports = {
    // ============================
    // Network Configuration
    // ============================
    networks: {
        mainnet: {
            name: "Ethereum Mainnet",
            chainId: 1,
            rpc: process.env.MAINNET_RPC_URL || "https://eth.llamarpc.com",
            // Uniswap V3 Contract Addresses on Mainnet
            factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH on Mainnet
        },
        sepolia: {
            name: "Sepolia Testnet",
            chainId: 11155111,
            rpc: process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
            // Uniswap V3 Contract Addresses on Sepolia
            factory: "0x0227628f3F023bb0B980b67D528571c95c6DaC1c",
            positionManager: "0x1238536071E1c677A632429e3655c799b22cDA52",
            weth: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", // WETH on Sepolia
        },
    },

    // ============================
    // Token Configuration
    // ============================
    tokens: {
        // USDT addresses per network
        usdt: {
            mainnet: "0xdAC17F958D2ee523a2206206994597C13D831ec7", // USDT on Mainnet
            sepolia: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0", // USDT on Sepolia (test)
        },
        // PSC token address (set after deployment)
        psc: {
            mainnet: process.env.PSC_MAINNET_ADDRESS || "",
            sepolia: process.env.PSC_SEPOLIA_ADDRESS || "",
        },
    },

    // ============================
    // Pool Configuration
    // ============================
    pool: {
        // Fee tier: 0.3% (most common for volatile pairs)
        // Options: 500 (0.05%), 3000 (0.3%), 10000 (1%)
        fee: 3000,

        // Initial price: 1 PSC = 0.01 USDT
        // This means 1 USDT = 100 PSC
        // Adjust based on your tokenomics
        initialPricePSCInUSDT: "0.01",

        // Liquidity amounts to add
        // These will be adjusted based on the initial price
        liquidity: {
            // USDT amount to add (in USDT, 6 decimals)
            usdtAmount: "1000", // 1000 USDT

            // PSC amount to add (in PSC, 18 decimals)
            // This will be calculated automatically based on initial price
            pscAmount: "", // Leave empty for auto-calculation
        },

        // Tick range for concentrated liquidity
        // Full range: -887272 to 887272
        // For concentrated: adjust based on expected price range
        tickLower: -887272, // Full range lower bound
        tickUpper: 887272,  // Full range upper bound
    },
};