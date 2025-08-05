// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "../donate/DonationTrackerUpgradeable.sol";

/**
 * @title DonationMetadataLib
 * @author drt-pREWA (Refactored)
 * @notice A library for generating on-chain metadata and SVG images for donation NFTs.
 * @dev This logic was extracted from DonationTrackerUpgradeable to resolve contract size limits.
 * It contains only pure and view functions and does not modify state.
 */
library DonationMetadataLib {
    using Strings for uint256;

    /**
     * @notice Generates the full token URI metadata JSON for a given donation.
     * @param d The Donation struct containing the details.
     * @param tokenId The ID of the token.
     * @return A data URI string containing the complete JSON metadata.
     */
    function generateURI(DonationTrackerUpgradeable.Donation memory d, uint256 tokenId) internal pure returns (string memory) {
        string memory amountStr = _formatAmount(uint256(d.amount), d.decimals);
        
        string memory attributes = string.concat(
            '{"trait_type":"Amount","value":"', amountStr, '"},',
            '{"trait_type":"Asset","value":"', d.symbol, '"},',
            '{"trait_type":"Timestamp","display_type":"date","value":"', uint256(d.timestamp).toString(), '"}'
        );
        
        string memory imageSVG = _generateSVG(tokenId, amountStr, d.symbol);
        string memory imageB64 = Base64.encode(bytes(imageSVG));
        string memory imageURI = string.concat('data:image/svg+xml;base64,', imageB64);
        
        string memory json = string.concat(
            '{"name":"Donation Certificate #', tokenId.toString(),
            '","description":"On-chain donation certificate",',
            '"image":"', imageURI, '",',
            '"attributes":[', attributes, ']}'
        );

        string memory jsonB64 = Base64.encode(bytes(json));
        return string.concat("data:application/json;base64,", jsonB64);
    }

    /**
     * @dev Formats a token amount into a human-readable decimal string, trimming trailing zeros.
     */
    function _formatAmount(uint256 amount, uint256 decimals) internal pure returns (string memory) {
        if (amount == 0) return "0";
        uint256 integer = amount / 10**decimals;
        uint256 fractional = amount % 10**decimals;
        if (fractional == 0) return integer.toString();

        string memory fractionalStr = fractional.toString();
        uint256 missingZeros = decimals - bytes(fractionalStr).length;
        if (missingZeros > 0) {
            bytes memory zeros = new bytes(missingZeros);
            for (uint i = 0; i < missingZeros; i++) {
                zeros[i] = "0";
            }
            fractionalStr = string(abi.encodePacked(zeros, fractionalStr));
        }

        uint256 endIndex = bytes(fractionalStr).length;
        while (endIndex > 0 && bytes(fractionalStr)[endIndex-1] == '0') {
            endIndex--;
        }

        if (endIndex == 0) return integer.toString();
        
        bytes memory sliced = new bytes(endIndex);
        for(uint i = 0; i < endIndex; i++) {
            sliced[i] = bytes(fractionalStr)[i];
        }

        return string(abi.encodePacked(integer.toString(), ".", string(sliced)));
    }

    /**
     * @dev Generates the SVG image data for the NFT certificate.
     */
    function _generateSVG(uint256 tokenId, string memory amount, string memory symbol) internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300">',
            '<rect width="100%" height="100%" fill="#f0f0f0"/>',
            '<text x="50%" y="35%" font-family="sans-serif" font-size="24" fill="black" text-anchor="middle">Dharitri Foundation</text>',
            '<text x="50%" y="50%" font-family="sans-serif" font-size="20" fill="black" text-anchor="middle">Certificate of Donation</text>',
            '<text x="50%" y="68%" font-family="monospace" font-size="18" fill="black" text-anchor="middle">',
            amount, " ", symbol, '</text>',
            '<text x="50%" y="85%" font-family="monospace" font-size="14" fill="black" text-anchor="middle">Token ID: ',
            tokenId.toString(), "</text></svg>"
        );
    }
}