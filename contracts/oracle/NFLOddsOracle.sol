// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract NFLOddsOracle {
  address public oracle;
  mapping(uint => bool) public usedIds;
  mapping(uint => Game) public games;

  struct Game {
    int16 homeOdds;
    int16 awayOdds;
  }

  constructor(address _oracle) {
    oracle = _oracle;
  }

  modifier onlyOracle() {
    require(msg.sender == oracle, "Only Oracle");
    _;
  }

  function makeGame(uint gameId, int16 homeOdds, int16 awayOdds) external onlyOracle {
    require(!usedIds[gameId], "game ID already used");
    usedIds[gameId] = true;
    Game memory game;
    game.homeOdds = homeOdds;
    game.awayOdds = awayOdds;
    games[gameId] = game;
  }

  function updateOdds(uint gameId, int16 homeOdds, int16 awayOdds) external onlyOracle {
    Game storage game = games[gameId];
    game.homeOdds = homeOdds;
    game.awayOdds = awayOdds;
  }

  function getOdds(uint gameId) external view returns (int16 homeOdds, int16 awayOdds) {
    Game storage game = games[gameId];
    return (game.homeOdds, game.awayOdds);
  }
}
