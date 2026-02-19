// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title OracleLib
 * @author Patrick Collins
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable - this is by design.
 * We want the DSCEngine to freeze if prices become stale. 
 * 
 * So if the Chainlink network explodes and you have a lot of money locked in the protocol... too bad. 
 */
library OracleLib {
    error OracleLib__StalePrice();
    
error OracleLib__StaleRound();
error OracleLib__InvalidPrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds
   


// Chainlink latestRoundData() returns:

// roundId: Sequential update ID (1, 2, 3...)
// answer: Price as int256 (e.g., 2500e8 = $2500 for 8 decimals)
// startedAt: Block when round began
// updatedAt: Block when price was set (CRITICAL for staleness)
// answeredInRound: Round where this answer was computed


    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

 // bug        
    if (answeredInRound < roundId) revert OracleLib__StaleRound();      
    if (answer <= 0) revert OracleLib__InvalidPrice();                  
    if (block.timestamp - updatedAt > TIMEOUT) revert OracleLib__StalePrice();  

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

  


    function getTimeout(AggregatorV3Interface /* chainlinkFeed */ ) public pure returns (uint256) {
        return TIMEOUT;
    }
}
