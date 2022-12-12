// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface INFLOddsOracle {
  function getOdds(uint gameId) external view returns (int16 homeOdds, int16 awayOdds);
}
