architecture

01.src/

-> lib/OracleLib.sol
-> DecentralizedStableCoin.sol.  // along with the test cases
-> DSCEngine.sol
script/ 


    /*//////////////////////////////////////////////////////////////
                                  BUGS
    //////////////////////////////////////////////////////////////*/

01. `Stale Round Attack`


=>> lib/OracleLib.sol

 Missing Chainlink round validation
 Risk: Stale price oracle manipulation

  3hr timestamp check → Blocks Chainlink downtime  ✅ 
❌ NO round mismatch check → Allows stale round attacks  
❌ NO price <= 0 check → Allows invalid prices


 `if (answeredInRound < roundId) revert OracleLib__StaleRound()`;      
    `if (answer <= 0) revert OracleLib__InvalidPrice()`;                  
    `if (block.timestamp - updatedAt > TIMEOUT) revert OracleLib__StalePrice()`;


     │   User deposits │
                    │    1 ETH        │
                    └─────────┬─────────┘
                              │
                              ▼
┌─────────────────────────────┼─────────────────────────────┐
│          OLD CODE           │           NEW CODE          │
│                   
├─────────────────────────────┼─────────────────────────────
│ 1. getUsdValue(ETH, 1e18)   │ 1. getUsdValue(ETH, 1e18)   
│    ↓                        │    ↓                        
│ 2. staleCheckLatestRoundData│ 2. staleCheckLatestRoundData
│    ↓                        │    ↓                        
│ ┌─────────────────────────┐ │ ┌─────────────────────────┐ 
│ │Chainlink:               │ │ │Chainlink:               │ 
│ │roundId = 3              │ │ │roundId = 3              │ 
│ │answeredInRound = 1      │ │ │answeredInRound = 1      │ 
│ │price = $2400 (STALE!)   │ │ │price = $2400 (STALE!)   │ 
│ │updatedAt = fresh        │ │ │updatedAt = fresh        │ 
│ └─────────────────────────┘ │ └─────────────────────────┘ 
│    ↓                        │    ↓                        
│ ┌─────────────────────────┐ │ ┌─────────────────────────┐ 
│ │✅ 3hr check PASSES      │ │ │❌ answeredInRound<roundId│ 
│ │← Only timestamp check   │ │ │  1 < 3 → REVERT!         │ 
│ └─────────────────────────┘ │ └─────────────────────────┘ 
│    ↓                        │     ↑ BLOCKED              
│ ┌─────────────────────────┐ │                             
│ │3. Collateral value =    │ │                             
│ │   $2400 ✓ (WRONG!)      │ │                             
│ └─────────────────────────┘ │                             
│    ↓                        │                             
│ ┌─────────────────────────┐ │                             
│ │4. Health Factor = 2.4   │ │                             
│ │   → Mint 1200 DSC OK!   │ │                             
│ └─────────────────────────┘ │                             
│    ↓                        │                             
└─────────────┬───────────────┘                             
              │                                               
              ▼                                               
┌─────────────────────────────┐                              
│5. REAL ETH PRICE = $2000 
  → Protocol loses $400!      │                               
└─────────────────────────────┘                              


Day 1:   $2400 → $2480 (3%) → Consensus ✅ roundId=10, answeredInRound=10
Day 2:   $2480 → $2650 (7%) → Consensus ✅ roundId=50, answeredInRound=50
Day 3:   $2650 → $2900 (9%) → Consensus ✅ roundId=100, answeredInRound=100
...
Day 7:   $4100 → $4300 (5%) → Consensus ✅ roundId=500, answeredInRound=500

Each step GRADUAL → Nodes agree → roundId == answeredInRound → PASS ✅
✅ GRADUAL WEEK PUMP (SAFE):
$2400 ── $2480 ── $2650 ── $2900 ── $3200 ── $3500 ── $4300
  │      │      │      │      │      │      │
Round10 Round50 Round100 etc... All consensus ✅

❌ SUDDEN 1MIN SPIKE (BLOCKED):
$2900 ──────────────────── $3500 (20%!)
Round149       Round150 incomplete → BLOCK
               Round151 consensus → UNBLOCK


           Attacker point of view:
           
           
               MARKET: ETH $10K (Round1 ✅) → $8K crash (Round2 ⏳ incomplete)
                    │
Attacker deposits 1 ETH → getUsdValue() → staleCheckLatestRoundData()
                    │
Chainlink returns: [roundId=2, price=$10K stale, answeredInRound=1, timestampFresh]
                    │
OLD CODE (timestamp only): 10min < 3hr → PASS ❌ $10K collateral value
                    │
NEW CODE (your fix): answeredInRound(1) < roundId(2) → REVERT StaleRound ✅
                    │
                    ├─ WITHOUT FIX ──> Mints 5000 DSC → Withdraws 1 ETH ($8K real)
                    │                      ↓
                    │                 PROFIT: $2K/ETH → $2M at scale 💥
                    │
                    └─ WITH FIX ──────> Transaction REVERTS → $0 loss 🛡️




02.  src/DSCEngine

 Incorrect total collateral calculation due to unnormalized decimals in getAccountCollateralValue.
 The main bug is that this getUsdValue returns a value with the token’s decimals,
  not a fixed 18‑decimal USD amount, and then getAccountCollateralValue blindly sums those mismatched values

 ❌  ❌  ❌  ❌370 line
  `function getUsdValue // main `
  `function getAccountCollateralValue // follows`

 ✅✅✅ 

 updated the getUsdValue 
 by writing ifelse conditions.




1. Goal of DSCEngine
   - Need to compare:
       a) User collateral value in USD
       b) User debt in DSC (18 decimals)
   - So protocol expects: "all USD values are in 18-decimal format"

-------------------------------------------------
2. Old behavior (BUG)
-------------------------------------------------
getAccountCollateralValue(user)
    |
    v
Loop over each collateral token:
    - Read amount user deposited for that token
    - Call getUsdValue(token, amount)
        |
        v
        getUsdValue (OLD)
            - Read Chainlink price (e.g. 1000 * 1e8)
            - Multiply: price * ADDITIONAL_FEED_PRECISION * amount / PRECISION
            - This math:
                • Normalizes price to 18 decimals
                • BUT final result keeps the token's decimals
                  (6-dec for USDC, 8-dec for WBTC, 18-dec for WETH, etc.)
        |
        v
    - Add that value into totalCollateralValueInUsd

Problem:
    - totalCollateralValueInUsd = sum of values with mixed decimals
        • Part of it 18-dec, part 6-dec, part 8-dec, ...
    - Health factor / collateralization checks compare this broken sum
      against 18-dec DSC debt
    - Result: wrong collateral value → under/overestimation → possible exploits

-------------------------------------------------
3. New behavior (FIXED)
-------------------------------------------------
getAccountCollateralValue(user)
    |
    v
Loop over each collateral token:
    - Read amount user deposited for that token
    - Call getUsdValue(token, amount)
        |
        v
        getUsdValue (FIXED)
            - Read Chainlink price
            - Read tokenDecimals (from IERC20Metadata)
            - Read priceDecimals (from priceFeed.decimals())
            - Normalize:
                • amount  -> amount1e18  (always 18 decimals)
                • price   -> price1e18   (always 18 decimals)
            - Compute:
                usdValue = (amount1e18 * price1e18) / 1e18
            - usdValue is now ALWAYS 18-decimal USD
        |
        v
    - Add usdValue into totalCollateralValueInUsd

Now:
    - totalCollateralValueInUsd is a sum of 18-decimal USD values only
    - It is directly comparable with 18-decimal DSC debt
    - Health factor, mint limits, and liquidation logic use consistent units
    - Decimal mismatch bug is removed



        src/DSCEngine.sol
    03. Adding Zero Checks for the construcor function✅


