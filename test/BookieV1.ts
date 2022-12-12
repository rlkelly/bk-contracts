import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

import { calculatePayout } from './utils';

describe("BookieV1", function () {
  async function deployBookieV1Fixture() {
    const [owner, oracle, alice, bob, charlie] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy();

    const RewardToken = await ethers.getContractFactory("RewardToken");
    const rewardToken = await RewardToken.deploy();

    const NFLScoreOracle = await ethers.getContractFactory("NFLScoreOracle");
    const nflScoreOracle = await NFLScoreOracle.connect(oracle).deploy(oracle.address);
    await nflScoreOracle.makeGame(
      12345,
      "HOME",
      "AWAY",
      1000000000,
    );

    const NFLOddsOracle = await ethers.getContractFactory("NFLOddsOracle");
    const nflOddsOracle = await NFLOddsOracle.deploy(owner.address);
    await nflOddsOracle.makeGame(0, -115, -110);

    const BookieV1 = await ethers.getContractFactory("NFLBookieV1", {
      signer: owner,
    });
    const sportGame = await BookieV1.deploy(token.address, nflOddsOracle.address, nflScoreOracle.address, rewardToken.address);

    const NFTImage = await ethers.getContractFactory("NFTImage");
    const nftImage = await NFTImage.deploy(sportGame.address);
    await sportGame.setNFTImage(nftImage.address);

    await token.mint(owner.address, 100_000 * 10 ** 6);
    await token.mint(alice.address, 100_000 * 10 ** 6);
    await token.mint(bob.address, 100_000 * 10 ** 6);
    await token.mint(charlie.address, 100_000 * 10 ** 6);

    await token.connect(owner).approve(sportGame.address, ethers.utils.parseUnits("1000", 18));
    await token.connect(alice).approve(sportGame.address, ethers.utils.parseUnits("1000", 18));
    await token.connect(bob).approve(sportGame.address, ethers.utils.parseUnits("1000", 18));
    await token.connect(charlie).approve(sportGame.address, ethers.utils.parseUnits("1000", 18));

    await sportGame.connect(owner).fundVault(0, 10 ** 6);
    await rewardToken.addMinter(sportGame.address);

    return { rewardToken, nflScoreOracle, sportGame, nftImage, token, owner, oracle, alice, bob, charlie };
  }

  describe("Test General Functionality", function () {
    it("Should be owned", async function () {
      const { sportGame, owner } = await loadFixture(deployBookieV1Fixture);
      expect(await sportGame.owner()).to.equal(owner.address);
    });

    it("should calculate payouts correctly", async function () {
      const { sportGame } = await loadFixture(deployBookieV1Fixture);
      expect(await sportGame.calculatePayout(100, -115)).to.equal(86);
    })

    it("Can create a game and take bets", async function () {
      const { nflScoreOracle, token, sportGame, owner, oracle, alice, bob } = await loadFixture(deployBookieV1Fixture);
      expect(await token.balanceOf(sportGame.address)).to.equal(10 ** 6);
      const spread = -75;
      await sportGame.connect(owner).makeGame(
        12345,
        0, // odds game id
        0,
        spread,
        "HOME vs AWAY",
      );
      await sportGame.connect(owner).toggleWagers(
        0,
        true,
      );

      await sportGame.connect(alice).makeWager(
        0,
        10 ** 6,
        true,
        -115,
      );
      expect(await sportGame.balanceOf(alice.address)).to.equal(1);

      const payoutAmount1 = calculatePayout(10 ** 6, -115);
      expect(await sportGame.getTotalAtRisk(0)).to.equal(10 ** 6 + payoutAmount1);
      expect(await sportGame.getSpareEscrowAmount(0)).to.equal(10 ** 6 - payoutAmount1);

      await sportGame.connect(bob).makeWager(
        0,
        10 ** 6,
        false,
        -110,
      );
      const payoutAmount2 = calculatePayout(10 ** 6, -110);
      const totalAtRisk = 10 ** 6 + Math.max(payoutAmount1, payoutAmount2);
      expect(await sportGame.getTotalAtRisk(0)).to.equal(totalAtRisk);
      expect(await sportGame.getSpareEscrowAmount(0)).to.equal(
        3 * 10 ** 6 - totalAtRisk
      );
      expect(await token.balanceOf(sportGame.address)).to.equal(2 * 10 ** 6 + 10 ** 6);
      const game = await sportGame.games(0);
      expect(game.totalWagers.homeOrUnderWagered).to.equal(10 ** 6);
      expect(game.totalWagers.awayOrOverWagered).to.equal(10 ** 6);

      await sportGame.connect(alice).makeWager(
        0,
        1300001,
        true,
        -115,
      );
      expect(await sportGame.getSpareEscrowAmount(0)).to.equal(0);
      await expect(sportGame.connect(alice).makeWager(
        0,
        100000,
        true,
        -115,
      )
      ).to.be.revertedWith("not sufficient escrow");

      const score = {
        home: 22,
        away: 14,
        quarter: 4,
      };

      await nflScoreOracle.updateScore(12345, score);
      await nflScoreOracle.finalizeGame(12345, score);

      expect(await token.balanceOf(alice.address)).to.equal(99997699999);
      await sportGame.connect(alice).claimWagers();
      expect(await token.balanceOf(alice.address)).to.equal(100002000000);

      expect(await token.balanceOf(bob.address)).to.equal(99999000000);
      await sportGame.connect(bob).claimWagers();
      expect(await token.balanceOf(bob.address)).to.equal(99999000000);
    });
  });

  describe("Test Bet Redemption", function () {
    it("Can claim lost bets", async function () {
      const { nflScoreOracle, token, sportGame, owner, oracle, alice, bob } = await loadFixture(deployBookieV1Fixture);

      const spread = -75;

      await sportGame.connect(owner).makeGame(
        12345,
        0, // odds game id
        0,
        spread,
        "HOME/AWAY",
      );
      await sportGame.connect(owner).toggleWagers(
        0,
        true,
      );

      const ITERATIONS = 50;
      for (let i = 0; i < ITERATIONS; i++) {
        await sportGame.connect(alice).makeWager(
          0,
          10 ** 4,
          true,
          -115,
        );
      }
      await sportGame.connect(bob).makeWager(
        0,
        10 ** 5,
        false,
        -110,
      );
      const score = {
        home: 22,
        away: 14,
        quarter: 4,
      };
      await nflScoreOracle.updateScore(12345, score);
      await nflScoreOracle.finalizeGame(12345, score);

      const balanceBefore = await token.balanceOf(owner.address);
      const _balance = await sportGame.gameBalance(0);

      await sportGame.claimLostWagers(0);
      const expectedWithdrawal = _balance.sub(ITERATIONS * (calculatePayout(10 ** 4, -115) + 10 ** 4));
      const expectedBalance = balanceBefore.add(expectedWithdrawal);
      expect(await token.balanceOf(owner.address)).to.equal(expectedBalance);
      await sportGame.claimLostWagers(0);
      expect(await token.balanceOf(owner.address)).to.equal(expectedBalance);

      const bobBeforeBalance = await token.balanceOf(owner.address);
      await sportGame.connect(bob).claimWagers();

      expect(await token.balanceOf(owner.address)).to.equal(bobBeforeBalance);
      await sportGame.connect(bob).claimWagers();
      expect(await token.balanceOf(owner.address)).to.equal(bobBeforeBalance);

      const aliceBeforeBalance = await token.balanceOf(alice.address);
      const tx = await sportGame.connect(alice).claimWagers();
      const receipt = await tx.wait();
      // console.log('gasCostForTxn', receipt.gasUsed);

      expect(await token.balanceOf(alice.address)).to.equal(aliceBeforeBalance.add(ITERATIONS * (10 ** 4 + calculatePayout(10 ** 4, -115))));
      await sportGame.connect(alice).claimWagers();
      expect(await token.balanceOf(alice.address)).to.equal(aliceBeforeBalance.add(ITERATIONS * (10 ** 4 + calculatePayout(10 ** 4, -115))));

      expect(await sportGame.gameBalance(0)).to.equal(0);
    });

    it("Can claim wagers", async function () {
      const { nflScoreOracle, token, sportGame, owner, oracle, alice, bob } = await loadFixture(deployBookieV1Fixture);

      const spread = -75;

      await sportGame.connect(owner).makeGame(
        12345,
        0, // odds game id
        0,
        spread,
        "HOME/AWAY",
      );
      await sportGame.connect(owner).toggleWagers(
        0,
        true,
      );

      for (let i = 0; i < 30; i++) {
        await sportGame.connect(alice).makeWager(
          0,
          10 ** 4,
          true,
          -115,
        );
      }
      await sportGame.connect(bob).makeWager(
        0,
        10 ** 5,
        false,
        -110,
      );
      const score = {
        home: 22,
        away: 14,
        quarter: 4,
      };
      await nflScoreOracle.updateScore(12345, score);
      await nflScoreOracle.finalizeGame(12345, score);

      const maxBet = await sportGame.getMaxBet(0, true);
      expect(maxBet).to.equal(965022);

      const bobBeforeBalance = await token.balanceOf(owner.address);
      await sportGame.connect(bob).claimWagers();

      expect(await token.balanceOf(owner.address)).to.equal(bobBeforeBalance);
      await sportGame.connect(bob).claimWagers();
      expect(await token.balanceOf(owner.address)).to.equal(bobBeforeBalance);

      const aliceBeforeBalance = await token.balanceOf(alice.address);
      await sportGame.connect(alice).claimWagers();
      expect(await token.balanceOf(alice.address)).to.equal(aliceBeforeBalance.add(30 * (10 ** 4 + calculatePayout(10 ** 4, -115))));
      await sportGame.connect(alice).claimWagers();
      expect(await token.balanceOf(alice.address)).to.equal(aliceBeforeBalance.add(30 * (10 ** 4 + calculatePayout(10 ** 4, -115))));

      // get balance of contract and check that all funds were withdrawn
      const _balance = await sportGame.gameBalance(0);
      const balanceBefore = await token.balanceOf(owner.address);
      await sportGame.claimLostWagers(0);
      const expectedWithdrawal = _balance;
      const expectedBalance = balanceBefore.add(expectedWithdrawal);

      expect(await token.balanceOf(owner.address)).to.equal(expectedBalance);
      // make sure it can be done twice
      await sportGame.claimLostWagers(0);
      expect(await token.balanceOf(owner.address)).to.equal(expectedBalance);

      expect(await sportGame.gameBalance(0)).to.equal(0);
      expect(await token.balanceOf(sportGame.address)).to.equal(0);
    });

    it("Can claim after bets", async function () {
      const { nftImage, sportGame, owner, alice } = await loadFixture(deployBookieV1Fixture);

      const spread = -75;

      await sportGame.connect(owner).makeGame(
        12345,
        0, // odds game id
        0,
        spread,
        "HOME/AWAY",
      );
      await sportGame.connect(owner).toggleWagers(
        0,
        true,
      );

      await sportGame.connect(owner).fundVault(0, 10 ** 8);
      await sportGame.connect(alice).makeWager(
        0,
        12510000,
        true,
        -115,
      );
      // const tokenUri = await sportGame.tokenURI(0);
    });

    it("Can calculates payouts properly", async function () {
      const { sportGame } = await loadFixture(deployBookieV1Fixture);

      const amount = 1000000;
      const odds = -500;
      const odds2 = 125;

      expect(await sportGame.calculateInversePayout(
        await sportGame.calculatePayout(amount, odds),
        odds
      )).to.equal(amount);

      expect(await sportGame.calculateInversePayout(
        await sportGame.calculatePayout(amount, odds2),
        odds2
      )).to.equal(amount);
    });

    it("Uses the Reservoir Funds", async function () {
      const { nflScoreOracle, sportGame, owner, alice, token } = await loadFixture(deployBookieV1Fixture);

      const spread = -75;

      await sportGame.connect(owner).makeGame(
        12345,
        0, // odds game id
        0,
        spread,
        "HOME/AWAY",
      );
      await sportGame.connect(owner).toggleWagers(
        0,
        true,
      );

      const maxBetSize = await sportGame.calculateInversePayout(10 ** 8, -115);
      await sportGame.connect(owner).fundResevoir(10 ** 8 - 10 ** 6);
      await sportGame.connect(alice).makeWager(
        0,
        maxBetSize,
        true,
        -115,
      );
      expect(await sportGame.getSpareEscrowAmount(0)).to.equal(0);
      expect(await sportGame.reservoirFunds()).to.equal(0);
      await expect(sportGame.connect(alice).makeWager(
        0,
        100,
        true,
        -115,
      )).to.be.revertedWith("not sufficient escrow");
      const score = {
        home: 0,
        away: 0,
        quarter: 0,
      };
      await nflScoreOracle.updateScore(12345, score);
      await nflScoreOracle.finalizeGame(12345, score);
      const balanceBefore = await token.balanceOf(owner.address);
      await sportGame.connect(owner).claimLostWagers(0);
      const balanceAfter = await token.balanceOf(owner.address);
      expect(balanceAfter.sub(balanceBefore)).to.equal(maxBetSize.add(10 ** 8));
    });
  });
});
