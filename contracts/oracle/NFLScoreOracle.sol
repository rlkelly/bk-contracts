// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/INFLScoreOracle.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

// this will be an upgradeable contract

contract NFLScoreOracle is INFLScoreOracle, Ownable2Step {
  address public oracle;
  uint public currentGame;
  uint public publishersCount;

  mapping(uint => Game) public games;
  mapping(uint => bool) public usedIds;
  mapping(address => bool) public publishers;
  mapping(uint => uint) public confirmations;

  constructor(address _oracle) {
    oracle = _oracle;
    publishers[oracle] = true;
  }

  modifier onlyOracle() {
    require(msg.sender == oracle, "Only Oracle");
    _;
  }

  function addPublisher(address _publisher) external onlyOwner {
    publishers[_publisher] = true;
  }

  function makeGame(uint gameId, string memory homeTeam, string memory awayTeam, uint startTime) public onlyOracle {
    require(!usedIds[gameId], "game ID already used");
    usedIds[gameId] = true;
    Game memory game;
    game.homeTeam = homeTeam;
    game.awayTeam = awayTeam;
    game.startTime = startTime;
    games[gameId] = game;
  }

  function updateScore(uint gameId, Score calldata score) public {
    require(publishers[msg.sender], "not a publisher");
    require(!games[gameId].finalized, "game already finalized");
    games[gameId].score = score;
  }

  function finalizeGame(uint gameId, Score calldata score) public onlyOracle {
    require(!games[gameId].finalized, "game already finalized");
    require(games[gameId].score.home == score.home && games[gameId].score.away == score.away, "invalid score");
    games[gameId].finalized = true;
  }

  function gameOutcome(uint gameId) external view returns(uint16 homeScore, uint16 awayScore, bool isFinalized) {
    Game memory game = games[gameId];
    homeScore = game.score.home;
    awayScore = game.score.away;
    isFinalized = game.finalized;
  }
}
