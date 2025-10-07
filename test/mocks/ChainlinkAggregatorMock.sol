// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IAggregatorV3MockLike {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

contract ChainlinkAggregatorMock is IAggregatorV3MockLike {
    uint8 public immutable overrideDecimals;
    int256 public currentAnswer;
    uint256 public currentUpdatedAt;

    constructor(uint8 _decimals, int256 _answer) {
        overrideDecimals = _decimals;
        currentAnswer = _answer;
        currentUpdatedAt = block.timestamp;
    }

    function setAnswer(
        int256 _answer
    ) external {
        currentAnswer = _answer;
        currentUpdatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return overrideDecimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80)
    {
        return (0, currentAnswer, 0, currentUpdatedAt, 0);
    }
}

