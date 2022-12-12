import { ethers } from "hardhat";

const USDC_ADDRESS = '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8';
function logToken(name: String, address: String) {
  console.log(`${name} was deployed to ${address}`);
}

async function main() {
  const [owner] = await ethers.getSigners();

  const RewardToken = await ethers.getContractFactory("RewardToken");
  const token = await RewardToken.deploy();
  logToken('token', token.address);

  const NFLOddsOracle = await ethers.getContractFactory("NFLOddsOracle");
  const oddsOracle = await NFLOddsOracle.deploy(owner.address);
  logToken('odds oracle', oddsOracle.address);

  const NFLScoreOracle = await ethers.getContractFactory("NFLScoreOracle");
  const scoreOracle = await NFLScoreOracle.deploy(owner.address);
  logToken('score oracle', scoreOracle.address);

  const BookieV1 = await ethers.getContractFactory("NFLBookieV1");
  const sportsGame = await BookieV1.deploy(
    USDC_ADDRESS, oddsOracle.address, scoreOracle.address, token.address,
  );
  logToken('bookie', sportsGame.address);

  await sportsGame.deployed();
  await token.addMinter(sportsGame.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
