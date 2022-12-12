// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IBetNFT {
    enum WagerType {
        spreadBet,
        overUnder
    }
    struct WagerData {
        uint gameId;
        WagerType wagerType;
        uint homeOrUnderWager;
        uint homeOrUnderPayout;
        uint awayOrOverWager;
        uint awayOrOverPayout;
    }

    event WagerMade(address sender, uint gameId, WagerType wagerType, uint wager, uint payout, bool isHome);

    function getWagerData(uint betId) external view returns (WagerData memory);
}
