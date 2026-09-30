// ============================================================
// UNISWAP V3 POOL DEPLOYMENT SCRIPT — PSC/USDT
// ============================================================
// This script creates a Uniswap V3 pool for PSC/USDT,
// initializes it with an initial price, and adds liquidity.
// ============================================================

const { ethers } = require("hardhat");
const config = require("./uniswap-config");

// ============================================================
// ABIs (Minimal interfaces for Uniswap V3 contracts)
// ============================================================

const FACTORY_ABI = [
    "function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool)",
    "function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool)",
];

const POOL_ABI = [
    "function initialize(uint160 sqrtPriceX96) external",
    "function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)",
    "function liquidity() external view returns (uint128)",
];

const POSITION_MANAGER_ABI = [
    "function mint((address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline)) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)",
];

const ERC20_ABI = [
    "function balanceOf(address account) external view returns (uint256)",
    "function decimals() external view returns (uint8)",
    "function symbol() external view returns (string)",
    "function approve(address spender, uint256 amount) external returns (bool)",
    "function allowance(address owner, address spender) external view returns (uint256)",
];

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Calculate sqrtPriceX96 for Uniswap V3
 * @param {string} price - Price of token1 in terms of token0 (token1/token0)
 * @param {number} decimals0 - Decimals of token0
 * @param {number} decimals1 - Decimals of token1
 * @returns {BigNumber} sqrtPriceX96
 */
function calculateSqrtPriceX96(price, decimals0, decimals1) {
    // Adjust for decimals
    const adjustedPrice = parseFloat(price) * Math.pow(10, decimals0 - decimals1);
    
    // sqrtPriceX96 = sqrt(price) * 2^96
    const Q96 = ethers.BigNumber.from(2).pow(96);
    const sqrtPrice = Math.sqrt(adjustedPrice);
    
    // Convert to BigNumber with high precision
    const sqrtPriceBN = ethers.utils.parseUnits(sqrtPrice.toFixed(18), 18);
    
    return sqrtPriceBN.mul(Q96).div(ethers.utils.parseUnits("1", 18));
}

/**
 * Get token order for Uniswap (token0 < token1)
 */
function sortTokens(tokenA, tokenB) {
    return tokenA.toLowerCase() < tokenB.toLowerCase()
        ? { token0: tokenA, token1: tokenB }
        : { token0: tokenB, token1: tokenA };
}

// ============================================================
// MAIN DEPLOYMENT FUNCTION
// ============================================================

async function main() {
    // Get network from environment or default to sepolia
    const networkName = process.env.NETWORK || "sepolia";
    const networkConfig = config.networks[networkName];

    if (!networkConfig) {
        throw new Error(`Network ${networkName} not configured`);
    }

    console.log("\n============================================================");
    console.log("  UNISWAP V3 POOL DEPLOYMENT — PSC/USDT");
    console.log("============================================================");
    console.log(`  Network: ${networkConfig.name}`);
    console.log(`  Chain ID: ${networkConfig.chainId}`);
    console.log("============================================================\n");

    // ============================================================
    // GET SIGNER
    // ============================================================
    const [deployer] = await ethers.getSigners();
    console.log(`Deployer address: ${deployer.address}`);

    const balance = await deployer.getBalance();
    console.log(`Deployer balance: ${ethers.utils.formatEther(balance)} ETH\n`);

    // ============================================================
    // GET TOKEN ADDRESSES
    // ============================================================
    const pscAddress = config.tokens.psc[networkName];
    const usdtAddress = config.tokens.usdt[networkName];

    if (!pscAddress) {
        throw new Error(`PSC token address not set for ${networkName}. Please set PSC_${networkName.toUpperCase()}_ADDRESS environment variable.`);
    }

    if (!usdtAddress) {
        throw new Error(`USDT token address not configured for ${networkName}`);
    }

    console.log("Token Addresses:");
    console.log(`  PSC: ${pscAddress}`);
    console.log(`  USDT: ${usdtAddress}\n`);

    // ============================================================
    // GET TOKEN CONTRACTS
    // ============================================================
    const pscToken = new ethers.Contract(pscAddress, ERC20_ABI, deployer);
    const usdtToken = new ethers.Contract(usdtAddress, ERC20_ABI, deployer);

    const pscDecimals = await pscToken.decimals();
    const usdtDecimals = await usdtToken.decimals();
    const pscSymbol = await pscToken.symbol();
    const usdtSymbol = await usdtToken.symbol();

    console.log("Token Information:");
    console.log(`  ${pscSymbol}: ${pscDecimals} decimals`);
    console.log(`  ${usdtSymbol}: ${usdtDecimals} decimals\n`);

    // ============================================================
    // SORT TOKENS (Uniswap requires token0 < token1)
    // ============================================================
    const { token0, token1 } = sortTokens(pscAddress, usdtAddress);
    const isPscToken0 = token0.toLowerCase() === pscAddress.toLowerCase();

    console.log("Token Order (Uniswap requirement):");
    console.log(`  token0: ${token0} (${isPscToken0 ? "PSC" : "USDT"})`);
    console.log(`  token1: ${token1} (${isPscToken0 ? "USDT" : "PSC"})\n`);

    // ============================================================
    // GET FACTORY CONTRACT
    // ============================================================
    const factory = new ethers.Contract(networkConfig.factory, FACTORY_ABI, deployer);

    // ============================================================
    // CHECK IF POOL EXISTS
    // ============================================================
    const fee = config.pool.fee;
    console.log(`Checking pool for fee tier ${fee / 10000}%...`);

    let poolAddress = await factory.getPool(token0, token1, fee);

    if (poolAddress === ethers.constants.AddressZero) {
        console.log("Pool does not exist. Creating pool...\n");

        // ============================================================
        // CREATE POOL
        // ============================================================
        const createTx = await factory.createPool(token0, token1, fee);
        const createReceipt = await createTx.wait();

        // Get pool address from event
        const poolCreatedEvent = createReceipt.events.find(e => e.event === "PoolCreated");
        if (poolCreatedEvent) {
            poolAddress = poolCreatedEvent.args.pool;
        } else {
            // Fallback: query again
            poolAddress = await factory.getPool(token0, token1, fee);
        }

        console.log(`Pool created at: ${poolAddress}\n`);
    } else {
        console.log(`Pool already exists at: ${poolAddress}\n`);
    }

    // ============================================================
    // INITIALIZE POOL WITH INITIAL PRICE
    // ============================================================
    const pool = new ethers.Contract(poolAddress, POOL_ABI, deployer);
    const slot0 = await pool.slot0();

    if (slot0.sqrtPriceX96.eq(0)) {
        console.log("Pool not initialized. Setting initial price...\n");

        // Calculate sqrtPriceX96 based on initial price
        // Price is token1/token0
        // If PSC is token0: price = USDT per PSC
        // If PSC is token1: price = PSC per USDT (inverse)
        
        let price;
        if (isPscToken0) {
            // PSC is token0, USDT is token1
            // Price = USDT/PSC = initialPricePSCInUSDT
            price = config.pool.initialPricePSCInUSDT;
        } else {
            // USDT is token0, PSC is token1
            // Price = PSC/USDT = 1 / initialPricePSCInUSDT
            price = (1 / parseFloat(config.pool.initialPricePSCInUSDT)).toString();
        }

        const sqrtPriceX96 = calculateSqrtPriceX96(price, parseInt(pscDecimals), parseInt(usdtDecimals));

        console.log(`Initial price: 1 PSC = ${config.pool.initialPricePSCInUSDT} USDT`);
        console.log(`sqrtPriceX96: ${sqrtPriceX96.toString()}\n`);

        const initTx = await pool.initialize(sqrtPriceX96);
        await initTx.wait();

        console.log("Pool initialized successfully!\n");
    } else {
        console.log("Pool already initialized.\n");
    }

    // ============================================================
    // CALCULATE LIQUIDITY AMOUNTS
    // ============================================================
    const usdtAmount = ethers.utils.parseUnits(
        config.pool.liquidity.usdtAmount,
        usdtDecimals
    );

    // Calculate PSC amount based on initial price
    let pscAmount;
    if (isPscToken0) {
        // PSC is token0, USDT is token1
        // Amount of PSC = USDT amount / price
        const pscAmountValue = parseFloat(config.pool.liquidity.usdtAmount) / parseFloat(config.pool.initialPricePSCInUSDT);
        pscAmount = ethers.utils.parseUnits(pscAmountValue.toFixed(parseInt(pscDecimals)), pscDecimals);
    } else {
        // USDT is token0, PSC is token1
        // Amount of PSC = USDT amount * price
        const pscAmountValue = parseFloat(config.pool.liquidity.usdtAmount) * parseFloat(config.pool.initialPricePSCInUSDT);
        pscAmount = ethers.utils.parseUnits(pscAmountValue.toFixed(parseInt(pscDecimals)), pscDecimals);
    }

    console.log("Liquidity Amounts:");
    console.log(`  USDT: ${ethers.utils.formatUnits(usdtAmount, usdtDecimals)} ${usdtSymbol}`);
    console.log(`  PSC: ${ethers.utils.formatUnits(pscAmount, pscDecimals)} ${pscSymbol}\n`);

    // ============================================================
    // APPROVE TOKENS
    // ============================================================
    console.log("Approving tokens for Position Manager...\n");

    // Approve USDT
    const usdtAllowance = await usdtToken.allowance(deployer.address, networkConfig.positionManager);
    if (usdtAllowance.lt(usdtAmount)) {
        const approveUsdtTx = await usdtToken.approve(networkConfig.positionManager, usdtAmount);
        await approveUsdtTx.wait();
        console.log(`  ${usdtSymbol} approved`);
    } else {
        console.log(`  ${usdtSymbol} already approved`);
    }

    // Approve PSC
    const pscAllowance = await pscToken.allowance(deployer.address, networkConfig.positionManager);
    if (pscAllowance.lt(pscAmount)) {
        const approvePscTx = await pscToken.approve(networkConfig.positionManager, pscAmount);
        await approvePscTx.wait();
        console.log(`  ${pscSymbol} approved`);
    } else {
        console.log(`  ${pscSymbol} already approved`);
    }

    console.log("");

    // ============================================================
    // ADD LIQUIDITY (MINT POSITION)
    // ============================================================
    console.log("Adding liquidity...\n");

    const positionManager = new ethers.Contract(
        networkConfig.positionManager,
        POSITION_MANAGER_ABI,
        deployer
    );

    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes

    // Prepare mint parameters
    const amount0Desired = isPscToken0 ? pscAmount : usdtAmount;
    const amount1Desired = isPscToken0 ? usdtAmount : pscAmount;

    const mintParams = {
        token0: token0,
        token1: token1,
        fee: fee,
        tickLower: config.pool.tickLower,
        tickUpper: config.pool.tickUpper,
        amount0Desired: amount0Desired,
        amount1Desired: amount1Desired,
        amount0Min: 0,
        amount1Min: 0,
        recipient: deployer.address,
        deadline: deadline,
    };

    const mintTx = await positionManager.mint(mintParams, {
        gasLimit: 3000000,
    });

    const mintReceipt = await mintTx.wait();

    console.log("Liquidity added successfully!\n");

    // ============================================================
    // DISPLAY RESULTS
    // ============================================================
    console.log("============================================================");
    console.log("  DEPLOYMENT SUMMARY");
    console.log("============================================================");
    console.log(`  Network:         ${networkConfig.name}`);
    console.log(`  Pool Address:    ${poolAddress}`);
    console.log(`  Token0:          ${token0}`);
    console.log(`  Token1:          ${token1}`);
    console.log(`  Fee Tier:        ${fee / 10000}%`);
    console.log(`  Initial Price:   1 PSC = ${config.pool.initialPricePSCInUSDT} USDT`);
    console.log(`  USDT Added:      ${ethers.utils.formatUnits(usdtAmount, usdtDecimals)}`);
    console.log(`  PSC Added:       ${ethers.utils.formatUnits(pscAmount, pscDecimals)}`);
    console.log(`  Transaction:     ${mintTx.hash}`);
    console.log("============================================================\n");

    // ============================================================
    // SAVE DEPLOYMENT INFO
    // ============================================================
    const deploymentInfo = {
        network: networkName,
        chainId: networkConfig.chainId,
        poolAddress: poolAddress,
        token0: token0,
        token1: token1,
        fee: fee,
        pscAddress: pscAddress,
        usdtAddress: usdtAddress,
        initialPrice: config.pool.initialPricePSCInUSDT,
        usdtAdded: ethers.utils.formatUnits(usdtAmount, usdtDecimals),
        pscAdded: ethers.utils.formatUnits(pscAmount, pscDecimals),
        transactionHash: mintTx.hash,
        timestamp: new Date().toISOString(),
    };

    const fs = require("fs");
    fs.writeFileSync(
        `./deployment-uniswap-${networkName}.json`,
        JSON.stringify(deploymentInfo, null, 2)
    );

    console.log(`Deployment info saved to: deployment-uniswap-${networkName}.json\n`);
}

// ============================================================
// EXECUTE
// ============================================================

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("\nDeployment failed:");
        console.error(error);
        process.exit(1);
    });