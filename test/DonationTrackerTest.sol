// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/donate/DonationTrackerUpgradeable.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/libraries/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

contract DonationTrackerTest is Test {
    DonationTrackerUpgradeable public donationTracker;
    AccessControl public accessControl;
    MockERC20 public token18;
    MockERC20 public token6;
    MockERC20 public token30;
    
    address owner = makeAddr("owner");
    address donor = makeAddr("donor");
    address treasury = makeAddr("treasury");
    address attacker = makeAddr("attacker");
    
    uint256 public constant COMPLIANCE_THRESHOLD = 1000 ether;

    function setUp() public {
        vm.startPrank(owner);
        
        // --- Phase 1: Deploy All Implementation Contracts ---
        AccessControl ac_implementation = new AccessControl();
        DonationTrackerUpgradeable dt_implementation = new DonationTrackerUpgradeable();
        token18 = new MockERC20("Token18", "T18", 18);
        token6 = new MockERC20("Token6", "T6", 6);
        token30 = new MockERC20("Token30", "T30", 18);
        
        // --- Phase 2: Deploy and Initialize Proxies ---
        // Deploy and Initialize AccessControl Proxy
        bytes memory acInitData = abi.encodeWithSelector(
            AccessControl.initialize.selector,
            owner // 'owner' gets DEFAULT_ADMIN_ROLE
        );
        ERC1967Proxy acProxy = new ERC1967Proxy(address(ac_implementation), acInitData);
        accessControl = AccessControl(address(acProxy));

        // Prepare Initialization Data for DonationTracker
        address[] memory tokens = new address[](2);
        tokens[0] = address(token18);
        tokens[1] = address(token6);
        
        string[] memory symbols = new string[](2);
        symbols[0] = "T18";
        symbols[1] = "T6";
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 6;
        
        bytes memory dtInitData = abi.encodeWithSelector(
            DonationTrackerUpgradeable.initialize.selector,
            address(accessControl),
            treasury,
            tokens,
            symbols,
            decimals
        );
        
        // Deploy and Initialize DonationTracker Proxy
        ERC1967Proxy dtProxy = new ERC1967Proxy(address(dt_implementation), dtInitData);
        donationTracker = DonationTrackerUpgradeable(payable(address(dtProxy)));
        
        // --- Phase 3: Configure Roles using the initialized AccessControl proxy ---
        accessControl.grantRole(donationTracker.RESCUE_ROLE(), owner);
        accessControl.grantRole(donationTracker.TOKEN_MANAGER_ROLE(), owner);
        accessControl.grantRole(donationTracker.TREASURY_MANAGER_ROLE(), owner);
        accessControl.grantRole(donationTracker.COMPLIANCE_ROLE(), owner);
        accessControl.grantRole(donationTracker.PAUSER_ROLE(), owner);
        
        // --- Phase 4: Fund Accounts ---
        token18.mint(donor, 10000 ether);
        token6.mint(donor, 10000 * 10**6);
        token30.mint(donor, 10000 ether);
        vm.deal(donor, 10000 ether);
        
        vm.stopPrank();
    }

    function _getDonationHash(address _donor, address token, uint256 amount) internal view returns (bytes32) {
        uint256 nonce = donationTracker.donationNonce(_donor);
        return keccak256(abi.encode(block.chainid, _donor, token, amount, nonce));
    }

    function test_InitialState() public view {
        assertEq(donationTracker.treasury(), treasury);
        assertEq(address(donationTracker.accessControl()), address(accessControl));
        assertTrue(donationTracker.supportedTokens(address(token18)));
        assertTrue(donationTracker.supportedTokens(address(token6)));
        assertFalse(donationTracker.supportedTokens(address(token30)));
    }

    function test_DonateBNB() public {
        uint256 amount = 0.5 ether;
        bytes32 donationHash = _getDonationHash(donor, address(0), amount);
        
        vm.expectEmit(true, true, true, true, address(donationTracker));
        emit DonationTrackerUpgradeable.DonationReceived(
            donor, 0, address(0), amount, block.timestamp, donationHash
        );
        
        vm.prank(donor);
        donationTracker.donateBNB{value: amount}(donationHash);
        
        assertEq(donationTracker.balanceOf(donor, 0), 1);
        assertEq(treasury.balance, amount);
    }

    function test_DonateBNB_RevertInvalidHash() public {
        uint256 amount = 0.5 ether;
        bytes32 wrongHash = keccak256("wrong");
        
        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.InvalidDonationHash.selector));
        donationTracker.donateBNB{value: amount}(wrongHash);
    }

    function test_DonateBNB_RevertZeroAmount() public {
        bytes32 donationHash = _getDonationHash(donor, address(0), 0);
        
        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
        donationTracker.donateBNB{value: 0}(donationHash);
    }

    function test_DonateBNB_RevertComplianceThreshold() public {
        uint256 amount = 1500 ether;
        bytes32 donationHash = _getDonationHash(donor, address(0), amount);
        
        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.ComplianceCheckRequired.selector, amount));
        donationTracker.donateBNB{value: amount}(donationHash);
    }

    function test_DonateERC20() public {
        uint256 amount = 500 * 10**18;
        bytes32 donationHash = _getDonationHash(donor, address(token18), amount);
        
        vm.prank(donor);
        token18.approve(address(donationTracker), amount);
        
        vm.expectEmit(true, true, true, true, address(donationTracker));
        emit DonationTrackerUpgradeable.DonationReceived(
            donor, 0, address(token18), amount, block.timestamp, donationHash
        );
        
        vm.prank(donor);
        donationTracker.donateERC20(address(token18), amount, donationHash);
        
        assertEq(donationTracker.balanceOf(donor, 0), 1);
        assertEq(token18.balanceOf(treasury), amount);
    }

    function test_DonateERC20_6Decimals() public {
        uint256 amount = 500 * 10**6;
        bytes32 donationHash = _getDonationHash(donor, address(token6), amount);
        
        vm.prank(donor);
        token6.approve(address(donationTracker), amount);
        
        vm.prank(donor);
        donationTracker.donateERC20(address(token6), amount, donationHash);
        
        assertEq(token6.balanceOf(treasury), amount);
    }

    function test_DonateERC20_RevertUnsupportedToken() public {
        uint256 amount = 500 * 10**18;
        
        vm.prank(donor);
        token30.approve(address(donationTracker), amount);
        
        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.TokenNotSupported.selector));
        donationTracker.donateERC20(address(token30), amount, bytes32(0));
    }

    function test_DonateERC20_RevertInsufficientAllowance() public {
        uint256 amount = 500 * 10**18;
        bytes32 donationHash = _getDonationHash(donor, address(token18), amount);
        
        vm.prank(donor);
        token18.approve(address(donationTracker), amount - 1);
        
        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(InsufficientAllowance.selector, amount - 1, amount));
        donationTracker.donateERC20(address(token18), amount, donationHash);
    }

    function test_DonateERC20_RevertComplianceThreshold() public {
        uint256 amount = 1500 * 10**6;
        bytes32 donationHash = _getDonationHash(donor, address(token6), amount);
        
        vm.prank(donor);
        token6.approve(address(donationTracker), amount);
        
        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.ComplianceCheckRequired.selector, amount));
        donationTracker.donateERC20(address(token6), amount, donationHash);
    }

    function test_ManageTokenSupport() public {
        vm.prank(owner);
        donationTracker.setTokenSupport(address(token30), "T30", 18, true);
        
        assertTrue(donationTracker.supportedTokens(address(token30)));
        
        vm.prank(owner);
        donationTracker.setTokenSupport(address(token30), "T30", 18, false);
        
        assertFalse(donationTracker.supportedTokens(address(token30)));
    }

    function test_ManageTokenSupport_RevertNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, donationTracker.TOKEN_MANAGER_ROLE()));
        donationTracker.setTokenSupport(address(token30), "T30", 18, true);
    }

    function test_ManageTokenSupport_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.InvalidTokenAddress.selector));
        donationTracker.setTokenSupport(address(0), "ZERO", 18, true);
    }

    function test_VerifyCompliance() public {
        vm.expectEmit(true, true, false, true, address(donationTracker));
        emit DonationTrackerUpgradeable.ComplianceVerified(donor);
        
        vm.prank(owner);
        donationTracker.verifyCompliance(donor);
    }

    function test_VerifyCompliance_RevertNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, donationTracker.COMPLIANCE_ROLE()));
        donationTracker.verifyCompliance(donor);
    }

    function test_DrainFunds() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS", 18);
        uint256 ethAmount = 5 ether;
        uint256 tokenAmount = 1000 * 10**18;
        
        vm.deal(address(donationTracker), ethAmount);
        unsupportedToken.mint(address(donationTracker), tokenAmount);

        uint256 ownerEthBefore = owner.balance;
        vm.prank(owner);
        donationTracker.rescueFunds(address(0));
        assertEq(owner.balance, ownerEthBefore + ethAmount);

        uint256 ownerTokenBefore = unsupportedToken.balanceOf(owner);
        vm.prank(owner);
        donationTracker.rescueFunds(address(unsupportedToken));
        assertEq(unsupportedToken.balanceOf(owner), ownerTokenBefore + tokenAmount);
    }
    
    function test_DrainFunds_RevertSupportedToken() public {
        token18.mint(address(donationTracker), 100 ether);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.UnauthorizedTokenRecovery.selector));
        donationTracker.rescueFunds(address(token18));
    }

    function test_DrainFunds_RevertNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, donationTracker.RESCUE_ROLE()));
        donationTracker.rescueFunds(address(0));
    }

    function test_UpdateTreasury() public {
        address newTreasury = makeAddr("new_treasury");
        
        vm.prank(owner);
        donationTracker.updateTreasury(newTreasury);
        
        assertEq(donationTracker.treasury(), newTreasury);
    }

    function test_UpdateTreasury_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DonationTrackerUpgradeable.InvalidTreasuryAddress.selector));
        donationTracker.updateTreasury(address(0));
    }

    function test_UpdateTreasury_RevertNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, donationTracker.TREASURY_MANAGER_ROLE()));
        donationTracker.updateTreasury(makeAddr("new_treasury"));
    }

    function test_TokenURI() public {
        uint256 amount = 123.456 ether;
        bytes32 donationHash = _getDonationHash(donor, address(0), amount);
        
        vm.prank(donor);
        donationTracker.donateBNB{value: amount}(donationHash);
        
        string memory uri = donationTracker.uri(0);
        assertGt(bytes(uri).length, 0);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function test_TokenURI_Formatting() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1.23456 ether;
        amounts[1] = 999 ether;
        amounts[2] = 0.000000000000000001 ether;
        
        for (uint i = 0; i < amounts.length; i++) {
            bytes32 donationHash = _getDonationHash(donor, address(0), amounts[i]);

            vm.prank(donor);
            donationTracker.donateBNB{value: amounts[i]}(donationHash);
            
            string memory uri = donationTracker.uri(i);
            assertGt(bytes(uri).length, 0);
            assertTrue(_startsWith(uri, "data:application/json;base64,"));
        }
    }

    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (strBytes.length < prefixBytes.length) return false;
        
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        return true;
    }

    function test_MaxValues() public {
        uint256 amount = 999 ether;
        
        bytes32 donationHash = _getDonationHash(donor, address(0), amount);
        vm.prank(donor);
        donationTracker.donateBNB{value: amount}(donationHash);
        
        donationHash = _getDonationHash(donor, address(token18), amount);
        vm.prank(donor);
        token18.approve(address(donationTracker), amount);
        vm.prank(donor);
        donationTracker.donateERC20(address(token18), amount, donationHash);
        
        assertEq(donationTracker.balanceOf(donor, 0), 1);
        assertEq(donationTracker.balanceOf(donor, 1), 1);
        assertEq(address(treasury).balance, amount);
        assertEq(token18.balanceOf(treasury), amount);
    }

    function test_ReentrancyProtection() public {
        ReentrancyExploiter exploiter = new ReentrancyExploiter(
            donationTracker, 
            address(token18)
        );
        
        uint256 donationAmount = 1 * 10**18;
        token18.mint(address(exploiter), 2 * 10**18);
        
        bytes32 validHash = _getDonationHash(address(exploiter), address(token18), donationAmount);

        vm.prank(address(exploiter));
        token18.approve(address(donationTracker), 2 * 10**18);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        exploiter.attack(validHash);
        vm.stopPrank();
    }
}

contract ReentrancyExploiter {
    DonationTrackerUpgradeable public donationTracker;
    IERC20 public token;
    uint256 public callCount = 0;

    constructor(DonationTrackerUpgradeable _donationTracker, address _token) {
        donationTracker = _donationTracker;
        token = IERC20(_token);
    }

    function attack(bytes32 validHash) public {
        donationTracker.donateERC20(address(token), 1 * 10**18, validHash);
    }
    
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        if (callCount > 0) return this.onERC1155Received.selector;
        callCount++;

        uint256 nonce = donationTracker.donationNonce(address(this));
        bytes32 reentrantHash = keccak256(
            abi.encode(block.chainid, address(this), address(token), 1 * 10**18, nonce)
        );
        donationTracker.donateERC20(address(token), 1 * 10**18, reentrantHash);
        return this.onERC1155Received.selector;
    }
}