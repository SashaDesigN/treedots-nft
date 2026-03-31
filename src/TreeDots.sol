// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title  TreeDots
 * @notice 1,000 fully on-chain generative three-dot NFTs.
 *         Tokens 0–19:   three green dots (rare genesis set).
 *         Tokens 20–999: three randomly colored dots (yellow / green / blue / red),
 *                        guaranteed never to be all-green.
 * @dev    All metadata encoded on-chain via abi.encodePacked + Base64.
 *         2 % ERC-2981 royalty paid to the deployer address.
 */
contract TreeDots is ERC721, ERC2981, Ownable {
    using Strings for uint256;

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    uint256 public constant MAX_SUPPLY     = 1_000;
    uint256 public constant SPECIAL_SUPPLY = 20;      // first 20 are three-green
    uint256 public constant MINT_PRICE     = 0.04 ether;
    uint96  public constant ROYALTY_BPS    = 200;     // 2 %

    // Dot color IDs
    uint8 private constant YELLOW = 0;
    uint8 private constant GREEN  = 1;
    uint8 private constant BLUE   = 2;
    uint8 private constant RED    = 3;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    uint256 private _totalMinted;

    /**
     * @dev 9 bytes packed per token: [c0, c1, c2, x0, x1, x2, y0, y1, y2]
     *      c* = color id (0–3)
     *      x*, y* = dot center position, stored in range [20, 250] → fits uint8
     */
    mapping(uint256 => bytes9) private _dots;

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error InsufficientPayment();
    error MaxSupplyReached();
    error WithdrawFailed();

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor() ERC721("Tree Dots", "TREEDOTS") Ownable(msg.sender) {
        _setDefaultRoyalty(msg.sender, ROYALTY_BPS);
    }

    // -----------------------------------------------------------------------
    // Mint
    // -----------------------------------------------------------------------

    function mint() external payable {
        if (msg.value < MINT_PRICE)    revert InsufficientPayment();
        if (_totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();

        uint256 tokenId = _totalMinted;
        unchecked { _totalMinted++; }

        _dots[tokenId] = _generateDots(tokenId);
        _safeMint(msg.sender, tokenId);
    }

    /**
     * @dev Pseudo-random dot generation.
     *      Uses block.prevrandao (EIP-4399) + tokenId + caller as entropy.
     *      Positions map to [20, 250] on the 300×300 canvas (dot radius = 22 px).
     */
    function _generateDots(uint256 tokenId) private view returns (bytes9) {
        bytes32 seed = keccak256(
            abi.encodePacked(block.prevrandao, tokenId, msg.sender, block.timestamp)
        );

        // Positions: 20 + (seed_byte % 231) → range [20, 250], max fits in uint8
        uint8 x0 = uint8(20 + uint8(seed[3]) % 231);
        uint8 x1 = uint8(20 + uint8(seed[4]) % 231);
        uint8 x2 = uint8(20 + uint8(seed[5]) % 231);
        uint8 y0 = uint8(20 + uint8(seed[6]) % 231);
        uint8 y1 = uint8(20 + uint8(seed[7]) % 231);
        uint8 y2 = uint8(20 + uint8(seed[8]) % 231);

        uint8 c0;
        uint8 c1;
        uint8 c2;

        if (tokenId < SPECIAL_SUPPLY) {
            // Genesis set: three green dots
            c0 = GREEN; c1 = GREEN; c2 = GREEN;
        } else {
            // Random colors 0–3
            c0 = uint8(seed[0]) % 4;
            c1 = uint8(seed[1]) % 4;
            c2 = uint8(seed[2]) % 4;

            // Guarantee no repeat of the three-green trait
            if (c0 == GREEN && c1 == GREEN && c2 == GREEN) {
                // Replace c2 with a deterministic non-green color
                // seed[9] % 3 → 0,1,2 → maps to Yellow(0), Blue(2), Red(3)
                uint8 r = uint8(seed[9]) % 3;
                c2 = r < 1 ? YELLOW : r == 1 ? BLUE : RED;
            }
        }

        // Pack 9 uint8 values into bytes9 via uint72 bit-shifting
        return bytes9(
            uint72(c0) << 64 | uint72(c1) << 56 | uint72(c2) << 48 |
            uint72(x0) << 40 | uint72(x1) << 32 | uint72(x2) << 24 |
            uint72(y0) << 16 | uint72(y1) <<  8 | uint72(y2)
        );
    }

    // -----------------------------------------------------------------------
    // Token URI  —  fully on-chain
    // -----------------------------------------------------------------------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        bytes9 d = _dots[tokenId];

        uint8   c0 = uint8(d[0]);
        uint8   c1 = uint8(d[1]);
        uint8   c2 = uint8(d[2]);
        uint256 x0 = uint256(uint8(d[3]));
        uint256 x1 = uint256(uint8(d[4]));
        uint256 x2 = uint256(uint8(d[5]));
        uint256 y0 = uint256(uint8(d[6]));
        uint256 y1 = uint256(uint8(d[7]));
        uint256 y2 = uint256(uint8(d[8]));

        // Build SVG using abi.encodePacked (returned as bytes for Base64 input)
        bytes memory svg = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" width="300" height="300">',
            '<rect width="300" height="300" fill="#0D0D0D" rx="12"/>',
            _circle(x0, y0, _colorHex(c0)),
            _circle(x1, y1, _colorHex(c1)),
            _circle(x2, y2, _colorHex(c2)),
            '</svg>'
        );

        // Build JSON metadata using abi.encodePacked; SVG is base64-inlined
        bytes memory metadata = abi.encodePacked(
            '{"name":"Tree Dots #',
            tokenId.toString(),
            '","description":"Fully on-chain generative three-dot art. 1,000 unique pieces.",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(svg),
            '","attributes":[',
            '{"trait_type":"Dot 1","value":"', _colorName(c0), '"},',
            '{"trait_type":"Dot 2","value":"', _colorName(c1), '"},',
            '{"trait_type":"Dot 3","value":"', _colorName(c2), '"}',
            ']}'
        );

        // Encode full JSON as base64 data URI using abi.encodePacked
        return string(
            abi.encodePacked("data:application/json;base64,", Base64.encode(metadata))
        );
    }

    function _circle(uint256 cx, uint256 cy, string memory fill)
        private pure returns (bytes memory)
    {
        return abi.encodePacked(
            '<circle cx="', cx.toString(),
            '" cy="', cy.toString(),
            '" r="22" fill="', fill, '"/>'
        );
    }

    function _colorHex(uint8 id) private pure returns (string memory) {
        if (id == YELLOW) return "#FFD700";
        if (id == GREEN)  return "#00C853";
        if (id == BLUE)   return "#2979FF";
        return "#FF1744"; // RED
    }

    function _colorName(uint8 id) private pure returns (string memory) {
        if (id == YELLOW) return "Yellow";
        if (id == GREEN)  return "Green";
        if (id == BLUE)   return "Blue";
        return "Red";
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    function totalSupply() external view returns (uint256) {
        return _totalMinted;
    }

    /**
     * @notice Returns the raw dot data for a token (useful for UIs / indexers).
     */
    function getDots(uint256 tokenId)
        external view
        returns (uint8 c0, uint8 c1, uint8 c2, uint8 x0, uint8 x1, uint8 x2, uint8 y0, uint8 y1, uint8 y2)
    {
        _requireOwned(tokenId);
        bytes9 d = _dots[tokenId];
        c0 = uint8(d[0]); c1 = uint8(d[1]); c2 = uint8(d[2]);
        x0 = uint8(d[3]); x1 = uint8(d[4]); x2 = uint8(d[5]);
        y0 = uint8(d[6]); y1 = uint8(d[7]); y2 = uint8(d[8]);
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    function withdraw() external onlyOwner {
        (bool ok,) = owner().call{value: address(this).balance}("");
        if (!ok) revert WithdrawFailed();
    }

    function setRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        _setDefaultRoyalty(receiver, feeBps);
    }

    // -----------------------------------------------------------------------
    // ERC-165
    // -----------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
