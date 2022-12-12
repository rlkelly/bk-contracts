// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IBetNFT.sol";

interface IBookie is IBetNFT {
    struct WagerTotal {
        uint homeOrUnderWagered;
        uint homeOrUnderPayout;
        uint awayOrOverWagered;
        uint awayOrOverPayout;
    }

    struct Game {
        uint oracleGameId;
        uint oddsGameId;
        uint starttime;
        string name;
        int16 spreadOrOverUnder;
        WagerType wagerType;

        // this allows for odds to be modified without affecting the oracle game odds
        // this is useful for incentivizing a specific side to balance the book
        Odds tease;

        WagerTotal totalWagers;

        bool finalized;
        bool isOpen;
    }

    struct Odds {
        int16 home;
        int16 away;
    }

    struct Wager {
        uint homeOrUnderWager;
        uint homeOrUnderPayout;
        uint awayOrOverWager;
        uint awayOrOverPayout;

        int16 spread;  // spread changes over time, but is fixed per wager
    }

    event GameIsOpenEvent(uint gameId, bool isOpen);
    event GameCreated(uint gameId);
    event GameFinalized(uint gameId);

    function games(uint gameId) external view returns (Game memory);
}
