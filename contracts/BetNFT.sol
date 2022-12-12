// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./interfaces/INFTImage.sol";
import "./interfaces/IBetNFT.sol";

contract BetNFT is ERC721Enumerable, Ownable2Step, IBetNFT {
  using Counters for Counters.Counter;

  INFTImage nftImage;
  WagerData[] public _wagerData;

  Counters.Counter private _tokenIds;

  constructor () ERC721("BOOKIE", "BK") {}
  mapping(address => mapping(uint => uint[])) public nftsPerGame;

  function _mintBet(uint gameId, WagerType wagerType, bool isHome, uint wager, uint payout, address recipient) internal {
    _safeMint(
      recipient,
      _tokenIds.current(),
      ""
    );
    _wagerData.push(WagerData(
      gameId,
      wagerType,
      isHome ? wager : 0,
      isHome ? payout : 0,
      isHome ? 0 : wager,
      isHome ? 0 : payout
    ));
    nftsPerGame[recipient][gameId].push(_tokenIds.current());
    _tokenIds.increment();
  }

  function setNFTImage(address _nftImage) external onlyOwner {
    nftImage = INFTImage(_nftImage);
  }

  function getTokenURI(uint256 tokenId) external view returns (string memory){
    return nftImage.getTokenURI(tokenId);
  }

  function getWagerData(uint wagerId) external view returns (WagerData memory) {
    return _wagerData[wagerId];
  }

  function tokenURI(uint256 tokenId)
      public
      view
      override(ERC721)
      returns (string memory)
  {
      return nftImage.getTokenURI(tokenId);
  }
}
