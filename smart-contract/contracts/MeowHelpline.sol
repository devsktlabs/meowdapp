// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import 'erc721a/contracts/extensions/ERC721AQueryable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './@rarible/royalties/contracts/impl/RoyaltiesV2Impl.sol';
import './@rarible/royalties/contracts/IERC2981.sol';
import './@rarible/royalties/contracts/LibPart.sol';
import './@rarible/royalties/contracts/LibRoyalties2981.sol';
import './@rarible/royalties/contracts/RoyaltiesV2.sol';


///////////////////////////////
//    *          )           //
//  (  `      ( /( (  (      //
//  )\))(  (  )\()))\))(   ' //
// ((_)()\ )\((_)\((_)()\ )  //
// (_()((_|(_) ((_)(())\_)() //
// |  \/  | __/ _ \ \((_)/ / //
// | |\/| | _| (_) \ \/\/ /  //
// |_|  |_|___\___/ \_/\_/   //
//                           //
///////////////////////////////                         

contract MeowHelpline is ERC721AQueryable, Ownable, ReentrancyGuard, RoyaltiesV2Impl {

 using Strings for uint256;
  string public contractURI;
  address royaltyReceiver;

  bytes32 public merkleRoot;
  mapping(address => bool) public whitelistClaimed;

  string public uriPrefix = '';
  string public uriSuffix = '.json';
  string public hiddenMetadataUri;
  
  uint256 public cost;
  uint256 public maxSupply;
  uint256 public maxMintAmountPerTx;

  bool public paused = true;
  bool public whitelistMintEnabled = false;
  bool public revealed = false;

  bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

  constructor(
    string memory _tokenName,
    string memory _tokenSymbol,
    uint256 _cost,
    uint256 _maxSupply,
    uint256 _maxMintAmountPerTx,
    string memory _hiddenMetadataUri
  ) ERC721A(_tokenName, _tokenSymbol) {
    setCost(_cost);
    maxSupply = _maxSupply;
    setMaxMintAmountPerTx(_maxMintAmountPerTx);
    setHiddenMetadataUri(_hiddenMetadataUri);
  }

  modifier mintCompliance(uint256 _mintAmount) {
    require(_mintAmount > 0 && _mintAmount <= maxMintAmountPerTx, 'Invalid mint amount!');
    require(totalSupply() + _mintAmount <= maxSupply, 'Max supply exceeded!');
    _;
  }

  modifier mintPriceCompliance(uint256 _mintAmount) {
    require(msg.value >= cost * _mintAmount, 'Insufficient funds!');
    _;
  }

  function whitelistMint(uint256 _mintAmount, bytes32[] calldata _merkleProof) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
    // Verify whitelist requirements
    require(whitelistMintEnabled, 'The whitelist sale is not enabled!');
    require(!whitelistClaimed[_msgSender()], 'Address already claimed!');
    bytes32 leaf = keccak256(abi.encodePacked(_msgSender()));
    require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), 'Invalid proof!');

    whitelistClaimed[_msgSender()] = true;
    _safeMint(_msgSender(), _mintAmount);
  }

  function mint(uint256 _mintAmount) public payable mintCompliance(_mintAmount) mintPriceCompliance(_mintAmount) {
    require(!paused, 'The contract is paused!');

    for (uint256 i = 0; i < _mintAmount; i++) {
        uint256 tokenId = totalSupply() + 1;

    // Royalties
      LibPart.Part[] memory _royalties = LibRoyalties2981.calculateRoyalties(owner(), 69000); // 6.9%% royalties to the owner
      _saveRoyalties(tokenId, _royalties);
      
      //mint token
      _safeMint(_msgSender(), _mintAmount);
  }
}
  function mintForAddress(uint256 _mintAmount, address _receiver) public mintCompliance(_mintAmount) onlyOwner {
    _safeMint(_receiver, _mintAmount);
  }

  function _startTokenId() internal view virtual override returns (uint256) {
    return 1;
  }

  function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
    require(_exists(_tokenId), 'ERC721Metadata: URI query for nonexistent token');

    if (revealed == false) {
      return hiddenMetadataUri;
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, _tokenId.toString(), uriSuffix))
        : '';
  }

  function setRevealed(bool _state) public onlyOwner {
    revealed = _state;
  }

  function setCost(uint256 _cost) public onlyOwner {
    cost = _cost;
  }

  function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx) public onlyOwner {
    maxMintAmountPerTx = _maxMintAmountPerTx;
  }

  function setHiddenMetadataUri(string memory _hiddenMetadataUri) public onlyOwner {
    hiddenMetadataUri = _hiddenMetadataUri;
  }

  function setUriPrefix(string memory _uriPrefix) public onlyOwner {
    uriPrefix = _uriPrefix;
  }

  function setUriSuffix(string memory _uriSuffix) public onlyOwner {
    uriSuffix = _uriSuffix;
  }

  function setPaused(bool _state) public onlyOwner {
    paused = _state;
  }

  function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
    merkleRoot = _merkleRoot;
  }

  function setWhitelistMintEnabled(bool _state) public onlyOwner {
    whitelistMintEnabled = _state;
  }

  //Royalty implementation
  function setRoyalties(uint _tokenID, address payable _royaltiesReceipientAddress, uint96 _percentageBasisPoints) public onlyOwner {
     LibPart.Part[] memory _royalties = new LibPart.Part[](1);
     _royalties[0].value = _percentageBasisPoints;
     _royalties[0].account = _royaltiesReceipientAddress;
     _saveRoyalties (_tokenID, _royalties);
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override (ERC721A) returns (bool){
      if(interfaceId == LibRoyalties2981._INTERFACE_ID_ROYALTIES){
        return true;
      }
      if(interfaceId == _INTERFACE_ID_ERC2981){
        return true;
      }
      return super.supportsInterface(interfaceId);
    }
    //////////////////////////////////////////////////////////////////////////////////
  function withdraw() public onlyOwner nonReentrant {
    // =============================================================================

    // This will transfer the remaining contract balance to the owner.
    // Do not remove this otherwise you will not be able to withdraw the funds.
    // =============================================================================
    (bool os, ) = payable(owner()).call{value: address(this).balance}('');
    require(os);
    // =============================================================================
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return uriPrefix;
  }
}
