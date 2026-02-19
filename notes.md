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


