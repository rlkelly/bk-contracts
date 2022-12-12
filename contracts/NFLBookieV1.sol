// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./BetNFT.sol";
import "./interfaces/IBookie.sol";
import "./interfaces/INFLScoreOracle.sol";
import "./interfaces/INFLOddsOracle.sol";
import "./interfaces/IERC20Mintable.sol";

contract NFLBookieV1 is BetNFT, IBookie {
    uint immutable maxWagers = 5000;  // prevents users from spamming.  May not be necessary but would like to avoid this.

    IERC20 public wagerToken;
    INFLOddsOracle public oddsOracle;
    uint numberOfGames;
    uint public totalWagered;
    uint public emergencyStartTime;
    uint public reservoirFunds;  // can be drawn from any game to fund it's gameBalance

    // reward token values
    address public bonusBetManager;  // this is for issuing bets from the rewards program
    IERC20Mintable public rewardToken; // rewards token

    INFLScoreOracle private scoreOracle;

    mapping(uint => uint) public gameBalance;
    mapping (uint => Game) public _games;
 
    constructor(IERC20 _wagerToken, INFLOddsOracle _oddsOracle, INFLScoreOracle _scoreOracle, IERC20Mintable _rewardToken) {
        wagerToken = _wagerToken;
        oddsOracle = _oddsOracle;
        scoreOracle = _scoreOracle;
        rewardToken = _rewardToken;
    }

    // public methods

    function makeGame(uint oracleGameId, uint oddsGameId, WagerType wagerType, int16 _spreadOrOverUnder, string calldata _name) public onlyOwner {
        /// @dev make a new game for users to wager on.  only callable by the owner
        /// @dev the spread is always the amount of points to add to the home team.  A -70 means the home team is a 7 point favorite.
        /// @param oracleGameId the gameID as defined in the score oracle contract
        /// @param oddsGameId the gameID as defined in the odds oracle contract
        /// @param wagerType the type of wager
        /// @param _spreadOrOverUnder the points set for the spread or overUnder amount, multiplied by 10.  This allows for half point spreads and over/unders.
        Game memory game;
        game.oracleGameId = oracleGameId;
        game.oddsGameId = oddsGameId;
        game.spreadOrOverUnder = _spreadOrOverUnder;
        // TODO: is this starttime?
        game.starttime = block.timestamp;
        game.name = _name;
        game.wagerType = wagerType;
        _games[numberOfGames++] = game;
        emit GameCreated(numberOfGames - 1);
    }

    function toggleWagers(uint gameId, bool _setIsOpen) public onlyOwner {
        _games[gameId].isOpen = _setIsOpen;
        emit GameIsOpenEvent(gameId, _setIsOpen);
    }

    function finalizeGame(uint gameId) public {
        require(!_games[gameId].finalized, "already finalized");
        (,,bool finalized) = getScore(gameId);
        require(finalized, "game is not finalized");

        _games[gameId].finalized = finalized;
        emit GameFinalized(gameId);
    }

    function makeBonusWager(address bonusReceiver, uint gameId, uint wager, bool forHomeOrUnder, int16 expectedOdds) public {
        /// @dev allows the bonus bet manager to make wagers where there's no funds at stake, but a prize can be won
        /// @param bonusReceiver since the wager is made on behalf of a user, the receiver must be provided
        /// @param gameId
        /// @param wager amount to wager
        /// @param forHomeOrUnder if the bet is on the home team or an under bet, depending on game type
        /// @param expectedOdds odds for the wager, so the invocation will fail if the odds have updated
        require(msg.sender == bonusBetManager, "Only bonusBetManager");
        require(wager > 0, "Bet Too Small");
        require(_games[gameId].isOpen, "Wagers are paused");

        (int16 homeOdds, int16 awayOdds) = getOdds(gameId);

        uint payoutAmount;
        if (forHomeOrUnder) {
            payoutAmount = calculatePayout(wager, homeOdds);
            require(homeOdds == expectedOdds, "Odds have changed since wager was made");
            _games[gameId].totalWagers.homeOrUnderPayout += payoutAmount;
            _mintBet(gameId, _games[gameId].wagerType, true, 0, payoutAmount, bonusReceiver);
        } else {
            payoutAmount = calculatePayout(wager, awayOdds);
            require(awayOdds == expectedOdds, "Odds have changed since wager was made");
            _games[gameId].totalWagers.awayOrOverPayout += payoutAmount;
            _mintBet(gameId, _games[gameId].wagerType, false, 0, payoutAmount, bonusReceiver);
        }
        emit WagerMade(bonusReceiver, gameId, _games[gameId].wagerType, 0, payoutAmount, forHomeOrUnder);

        int spareEscrow = getSpareEscrowAmount(gameId);
        if (spareEscrow < 0) {
            if (abs(spareEscrow) <= reservoirFunds) {
                gameBalance[gameId] += abs(spareEscrow);
                reservoirFunds -= abs(spareEscrow);
            }
        }
        require(getSpareEscrowAmount(gameId) >= 0, "not sufficient escrow");
    }

    function makeWager(uint gameId, uint wager, bool forHomeOrUnder, int16 expectedOdds) public {
        /// @notice this is the endpoint to make a wager for a specific gameId
        /// @notice an NFT is minted to represent the user's bet
        /// @param gameId
        /// @param wager amount to wager
        /// @param forHomeOrUnder if the bet is on the home team or an under bet, depending on game type
        /// @param expectedOdds odds for the wager, so the invocation will fail if the odds have updated
        require(wager > 0, "Bet Too Small");
        require(_games[gameId].isOpen, "Wagers are paused");
        require(balanceOf(msg.sender) < maxWagers, "too many open wagers");

        // For now, wager bonus will always be double rewards for NFL
        rewardToken.mint(msg.sender, wager * 2);

        wagerToken.transferFrom(msg.sender, address(this), wager);
        gameBalance[gameId] += wager;

        (int16 homeOrUnderOdds, int16 awayOrOverOdds) = getOdds(gameId);

        uint payoutAmount;
        if (forHomeOrUnder) {
            payoutAmount = calculatePayout(wager, homeOrUnderOdds);
            require(homeOrUnderOdds == expectedOdds, "Odds have changed since wager was made");

            _games[gameId].totalWagers.homeOrUnderWagered += wager;
            _games[gameId].totalWagers.homeOrUnderPayout += payoutAmount;

            _mintBet(gameId, _games[gameId].wagerType, true, wager, payoutAmount, msg.sender);
        } else {
            payoutAmount = calculatePayout(wager, awayOrOverOdds);
            require(awayOrOverOdds == expectedOdds, "Odds have changed since wager was made");

            _games[gameId].totalWagers.awayOrOverWagered += wager;
            _games[gameId].totalWagers.awayOrOverPayout += payoutAmount;

            _mintBet(gameId, _games[gameId].wagerType, false, wager, payoutAmount, msg.sender);
        }

        int spareEscrow = getSpareEscrowAmount(gameId);
        if (spareEscrow < 0) {
            if (abs(spareEscrow) <= reservoirFunds) {
                gameBalance[gameId] += abs(spareEscrow);
                reservoirFunds -= abs(spareEscrow);
            }
        }
        emit WagerMade(msg.sender, gameId, _games[gameId].wagerType, wager, payoutAmount, forHomeOrUnder);
        require(getSpareEscrowAmount(gameId) >= 0, "not sufficient escrow");
    }

    function claimLostWagers(uint gameId) public onlyOwner {
        Game storage game = _games[gameId];
        (uint16 homeScore, uint16 awayScore, bool finalized) = getScore(gameId);
        require(finalized, "game is not over");

        uint _balance = gameBalance[gameId];

        // start with total balance and subtract obligations
        uint totalClaimable = _balance;
        int16 _rawSpreadOrOver = game.spreadOrOverUnder;

        // win on tie
        bool awayOrOverWinsOnTie = (_rawSpreadOrOver / 10) * 10 != _rawSpreadOrOver;
        int16 _spreadOrOver = _rawSpreadOrOver / 10;
        (bool isTie,, bool awayOrOverWins) = _isTie(game.wagerType, homeScore, awayScore, _spreadOrOver);

        if (isTie) {
            if (awayOrOverWinsOnTie) {
                totalClaimable -= game.totalWagers.awayOrOverWagered + game.totalWagers.awayOrOverPayout;
            } else {
                totalClaimable -= game.totalWagers.awayOrOverWagered + game.totalWagers.homeOrUnderWagered;
            }
        } else if (awayOrOverWins) {
            totalClaimable -= game.totalWagers.awayOrOverWagered + game.totalWagers.awayOrOverPayout;
        } else {
            totalClaimable -= game.totalWagers.homeOrUnderWagered + game.totalWagers.homeOrUnderPayout;
        }
        gameBalance[gameId] -= totalClaimable;
        wagerToken.transfer(owner(), totalClaimable);
    }

    function redeemWager(uint nftId) public {
        require(msg.sender == ownerOf(nftId) || msg.sender == owner(),
            "Can only be invoked by contract or NFT owner");

        WagerData memory wager = _wagerData[nftId];
        uint gameId = _wagerData[nftId].gameId;
        (uint16 homeScore, uint16 awayScore, bool finalized) = getScore(gameId);

        require(finalized, "Game not yet finalized");

        int16 _rawSpreadOrOver = _games[gameId].spreadOrOverUnder;

        // win on tie
        bool awayOrOverWinsOnTie = (_rawSpreadOrOver / 10) * 10 != _rawSpreadOrOver;
        int16 _spreadOrOver = _rawSpreadOrOver / 10;
        (bool isTieGame, bool homeOrUnderWins, bool awayOrOverWins) = _isTie(_games[gameId].wagerType, homeScore, awayScore, _spreadOrOver);

        // TODO: should we remove all wagered amounts at end of loop?
        if (wager.homeOrUnderWager > 0) {
            if (isTieGame) {
                if (!awayOrOverWinsOnTie) {
                    wagerToken.transfer(ownerOf(nftId), wager.homeOrUnderWager);
                    gameBalance[gameId] -= wager.homeOrUnderWager;
                    _games[gameId].totalWagers.homeOrUnderWagered -= wager.homeOrUnderWager;
                }
            } else if (homeOrUnderWins) {
                wagerToken.transfer(ownerOf(nftId), wager.homeOrUnderWager + wager.homeOrUnderPayout);
                gameBalance[gameId] -= wager.homeOrUnderWager + wager.homeOrUnderPayout;
                _games[gameId].totalWagers.homeOrUnderWagered -= wager.homeOrUnderWager;
                _games[gameId].totalWagers.homeOrUnderPayout -= wager.homeOrUnderPayout;
            }
        }
        if (wager.awayOrOverWager > 0) {
            if (isTieGame) {
                if (awayOrOverWinsOnTie) {
                    wagerToken.transfer(ownerOf(nftId), wager.awayOrOverWager + wager.awayOrOverPayout);
                    gameBalance[gameId] -= wager.awayOrOverWager + wager.awayOrOverPayout;
                    _games[gameId].totalWagers.awayOrOverWagered -= wager.awayOrOverWager;
                    _games[gameId].totalWagers.awayOrOverPayout -= wager.awayOrOverPayout;
                } else {
                    wagerToken.transfer(ownerOf(nftId), wager.awayOrOverWager);
                    gameBalance[gameId] -= wager.awayOrOverWager;
                    _games[gameId].totalWagers.awayOrOverWagered -= wager.awayOrOverWager;
                }
            } else if (awayOrOverWins) {
                wagerToken.transfer(ownerOf(nftId), wager.awayOrOverWager + wager.awayOrOverPayout);
                _games[gameId].totalWagers.awayOrOverWagered -= wager.awayOrOverWager;
                _games[gameId].totalWagers.awayOrOverPayout -= wager.awayOrOverPayout;
                gameBalance[gameId] -= wager.awayOrOverWager + wager.awayOrOverPayout;
            }
        }
        _burn(nftId);
    }

    function claimWagers() public {
        uint tokenBalance = balanceOf(msg.sender);

        uint i = tokenBalance;
        while (i > 0) {
            i--;
            // remove last element from wagers
            uint nftId = tokenOfOwnerByIndex(msg.sender, i);
            if (_checkIfFinalized(nftId)) {
                redeemWager(nftId);
            }
        }
    }

    function fundVault(uint gameId, uint128 amount) public {
        /// @dev Funds the vault for a specific game
        /// @param gameId game to fund
        /// @param amount amount of funds to transfer to individual game vault
        wagerToken.transferFrom(msg.sender, address(this), amount);
        gameBalance[gameId] += amount;
    }

    function fundResevoir(uint128 amount) public {
        /// @notice The reservoir is a general fund that all games will pull from when bets are made
        /// @notice This allows committing funds to the contract without having to individually fund games
        /// @dev Funds the general reservoir, which game vaults will pull from if underfunded
        /// @param amount amount of funds to transfer to reservoir
        wagerToken.transferFrom(msg.sender, address(this), amount);
        reservoirFunds += amount;
    }

    function withdrawResevoir() onlyOwner public {
        /// @dev Pull funds from reservoir
        /// @dev only callable by owner
        wagerToken.transfer(owner(), reservoirFunds);
        reservoirFunds = 0;
    }

    function updateTeaseOdds(uint gameId, int16 newHomeTease, int16 newAwayTease) public onlyOwner {
        /// This allows for the DAO to tease the odds to incentize a balanced book
        require(abs(newHomeTease) <= 10, "home tease > 10");
        _games[gameId].tease.home = newHomeTease;
        require(abs(newAwayTease) <= 10, "away tease > 10");
        _games[gameId].tease.away = newAwayTease;
    }

    function updateScoreOracle(address _scoreOracle) public onlyOwner {
        scoreOracle = INFLScoreOracle(_scoreOracle);
    }

    function updateOddsOracle(address _oddsOracle) public onlyOwner {
        oddsOracle = INFLOddsOracle(_oddsOracle);
    }

    function _checkIfFinalized(uint nftId) internal view returns(bool) {
        uint gameId = _wagerData[nftId].gameId;
        (,, bool finalized) = getScore(gameId);
        return finalized;
    }

    // VIEWS

    function getWagers(uint gameId, address user) public view returns(WagerData[] memory) {
        uint tokenBalance = balanceOf(user);
        WagerData[] memory userWagers = new WagerData[](tokenBalance);
        uint i = tokenBalance;
        while (i > 0) {
            i--;
            uint nftId = tokenOfOwnerByIndex(user, i);
            if (_wagerData[nftId].gameId == gameId) {
                userWagers[i] = _wagerData[nftId];
            }
        }
        return userWagers;
    }

    function getOdds(uint gameId) public view returns (int16 homeOdds, int16 awayOdds) {
        Game memory game = _games[gameId];
        (int16 _homeOdds, int16 _awayOdds) = oddsOracle.getOdds(game.oddsGameId);
        homeOdds = _homeOdds + _games[gameId].tease.home;
        awayOdds = _awayOdds + _games[gameId].tease.away;
    }

    function getScore(uint gameId) public view returns(uint16 homeScore, uint16 awayScore, bool finalized) {
        Game memory game = _games[gameId];
        (homeScore, awayScore, finalized) = scoreOracle.gameOutcome(game.oracleGameId);
    }

    function getSpareEscrowAmount(uint gameId) public view returns(int) {
        int totalAtRisk = int(getTotalAtRisk(gameId));
        uint currentBalance = gameBalance[gameId];
        return int(currentBalance) - totalAtRisk;
    }

    function getMaxBet(uint gameId, bool isHome) public view returns(uint) {
        (int16 homeOdds, int16 awayOdds) = getOdds(gameId);
        if (isHome) {
            uint maxPayout = gameBalance[gameId] - homeTotalAtRisk(gameId);
            return calculateInversePayout(maxPayout, homeOdds);
        } else {
            uint maxPayout = gameBalance[gameId] - awayTotalAtRisk(gameId);
            return calculateInversePayout(maxPayout, awayOdds);
        }
    }

    function homeTotalAtRisk(uint gameId) public view returns(uint) {
        return _games[gameId].totalWagers.homeOrUnderWagered + _games[gameId].totalWagers.homeOrUnderPayout;
    }

    function awayTotalAtRisk(uint gameId) public view returns(uint) {
        return _games[gameId].totalWagers.awayOrOverWagered + _games[gameId].totalWagers.awayOrOverPayout;
    }

    function getTotalAtRisk(uint gameId) public view returns(uint totalAtRisk) {
        uint homeTotal = homeTotalAtRisk(gameId);
        uint awayTotal = awayTotalAtRisk(gameId);
        if (homeTotal > awayTotal) {
            totalAtRisk = homeTotal;
        } else {
            totalAtRisk = awayTotal;
        }
    }

    function games(uint gameId) external view returns (Game memory) {
        return _games[gameId];
    }

    function getTotalWagers(address user, uint gameId) external view returns (uint homeWagerAmount, uint homePayoutAmount, uint awayWagerAmount, uint awayPayoutAmount) {
        uint tokenBalance = balanceOf(user);

        uint i = tokenBalance;
        while (i > 0) {
            i--;
            // remove last element from wagers
            uint nftId = tokenOfOwnerByIndex(user, i);
            if (_wagerData[nftId].gameId == gameId) {
                homeWagerAmount += _wagerData[nftId].homeOrUnderWager;
                awayWagerAmount += _wagerData[nftId].awayOrOverWager;
                homePayoutAmount += _wagerData[nftId].homeOrUnderPayout;
                awayPayoutAmount += _wagerData[nftId].awayOrOverPayout;
            }
        }
    }

    // PURE FUNCTIONS

    function _isTie(WagerType wagerType, uint homeScore, uint awayScore, int16 spreadOrOver) private pure returns(bool, bool, bool) {
        if (wagerType == WagerType.spreadBet) {
            int16 convertedHomeScore = int16(int(uint(homeScore))) + int16(spreadOrOver);
            int16 convertedAwayScore = int16(int(uint(awayScore)));
            bool isTie = convertedHomeScore == convertedAwayScore;
            bool homeWins = convertedHomeScore > convertedAwayScore;
            bool awayWins = convertedHomeScore < convertedAwayScore;
            return (isTie, homeWins, awayWins);
        } else {
            int16 totalPoints = int16(int(uint(homeScore))) + int16(int(uint(awayScore)));
            bool isTie = spreadOrOver == totalPoints;
            bool underWins = totalPoints < spreadOrOver;
            bool overWins = totalPoints > spreadOrOver;
            return (isTie, underWins, overWins);
        }
    }

    function calculatePayout(uint amount, int16 odds) public pure returns(uint) {
        if (odds < 0) {
            return (amount * 100 / uint(int(-1 * odds)));
        }
        return (amount * uint(int(odds))) / 100;
    }

    function calculateInversePayout(uint amount, int16 odds) public pure returns(uint) {
        if (odds < 0) {
            return (amount * uint(int(-1 * odds))) / 100;
        } else {
            return (amount * 100) / uint(int(odds));
        }
    }

    function abs(int x) private pure returns (uint) {
        return x >= 0 ? uint(x) : uint(-x);
    }

    // GOVERNANCE EMERGENCY FUNCTIONS

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (_token != wagerToken) {
            _token.transfer(to, amount);
        }
    }

    function requestEmergencyWithdrawFunds() public onlyOwner {
        /// Start the timer to withdraw funds in case funds are trapped
        emergencyStartTime = block.timestamp;
    }

    function emergencyWithdrawFunds(
        uint256 amount,
        address to
    ) public onlyOwner {
        /// @dev emergency withdraw with a 30 day timelock
        require(emergencyStartTime != 0, "timeframe not started");
        require(block.timestamp > emergencyStartTime + 30 days, "must wait 30 days for emergency withdraw");
        wagerToken.transfer(to, amount);
    }

    function isWinner(uint nftId) public view returns (bool isTie, bool _winner, bool finalized) {
        WagerData memory wager = _wagerData[nftId];
        uint gameId = _wagerData[nftId].gameId;
        (uint16 homeScore, uint16 awayScore, bool _finalized) = getScore(gameId);
        // TODO: should this revert?  It would require checking for finalized in claimWagers
        if (!_finalized) {
            return (false, false, false);
        }

        int16 _rawSpreadOrOver = _games[gameId].spreadOrOverUnder;
        bool awayOrOverWinsOnTie = (_rawSpreadOrOver / 10) * 10 != _rawSpreadOrOver;
        int16 _spreadOrOver = _rawSpreadOrOver / 10;
        (bool isTieGame, bool homeOrUnderWins, bool awayOrOverWins) = _isTie(_games[gameId].wagerType, homeScore, awayScore, _spreadOrOver);
        if (wager.homeOrUnderPayout > 0) {
            return (isTieGame && !awayOrOverWinsOnTie, homeOrUnderWins, finalized);
        } else {
            return (isTieGame && !awayOrOverWinsOnTie, awayOrOverWins || isTieGame && awayOrOverWinsOnTie, finalized);
        }
    }
}
