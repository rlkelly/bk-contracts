// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface INFTImage {
  function getTokenURI(uint256 tokenId) external view returns (string memory);
}
