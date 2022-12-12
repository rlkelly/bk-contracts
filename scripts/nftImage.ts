import { ethers } from "hardhat";

const GAME_CONTRACT = 'INSERT HERE'

async function main() {
  const NFTImage = await ethers.getContractFactory("NFTImage");
  const nftImage = await NFTImage.deploy(GAME_CONTRACT);
  const bookie = await ethers.getContractAt("NFLBookieV1", GAME_CONTRACT);
  await bookie.setNFTImage(nftImage.address);
  console.log(nftImage.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
