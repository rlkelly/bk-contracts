// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface INFLScoreOracle {
  struct Score {
    uint16 home;
    uint16 away;
    uint8 quarter;
  }

  struct Game {
    string homeTeam;
    string awayTeam;
    uint startTime;
    bool finalized;

    Score score;
  }

  function gameOutcome(uint gameId) external view returns(uint16 homeScore, uint16 awayScore, bool isFinalized);
}
