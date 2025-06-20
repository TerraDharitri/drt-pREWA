// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/core/pREWAToken.sol";
import "../contracts/core/interfaces/IpREWAToken.sol";
import "../contracts/interfaces/IEmergencyAware.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract PREWATokenTest is Test {
    PREWAToken token;
    MockEmergencyController mockEC;
    MockAccessControl mockAC;

    address owner; 
    address user1;
    address user2;
    address blacklistedUser;
    address minterUser;
    address pauserUser;
    address emergencyControllerAdmin; 
    address proxyAdmin;

    string constant TOKEN_NAME = "pREWA Token";
    string constant TOKEN_SYMBOL = "PREWA";
    uint8 constant TOKEN_DECIMALS = 18;
    uint256 constant INITIAL_SUPPLY = 1_000_000 * (10**TOKEN_DECIMALS);
    uint256 constant CAP = 10_000_000 * (10**TOKEN_DECIMALS);


    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        blacklistedUser = makeAddr("blacklistedUser");
        minterUser = makeAddr("minterUser");
        pauserUser = makeAddr("pauserUser");
        emergencyControllerAdmin = makeAddr("ecAdmin"); 
        proxyAdmin = makeAddr("proxyAdmin");

        mockEC = new MockEmergencyController(); 
        mockAC = new MockAccessControl();

        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.PAUSER_ROLE(), pauserUser, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.MINTER_ROLE(), minterUser, true);

        PREWAToken logic = new PREWAToken();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        token = PREWAToken(payable(address(proxy)));
        token.initialize(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS,
            INITIAL_SUPPLY,
            CAP,
            address(mockAC),
            address(mockEC),
            owner
        );
        
        vm.prank(owner);
        mockAC.setRole(mockAC.PAUSER_ROLE(), address(token), true);

        vm.prank(owner);
        token.addMinter(minterUser);
    }

    function test_Initialize_Success() public view { 
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.decimals(), TOKEN_DECIMALS);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.cap(), CAP);
        assertEq(address(token.accessControl()), address(mockAC));
        assertEq(address(token.emergencyController()), address(mockEC));
        assertEq(token.owner(), owner);
        assertTrue(token.isMinter(owner));
        assertEq(token.getBlacklistTimelockDuration(), 1 days);
    }
    
    function test_Initialize_NoInitialSupply() public {
        PREWAToken logic = new PREWAToken();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        PREWAToken noSupplyToken = PREWAToken(payable(address(proxy)));
        noSupplyToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, 0, CAP, address(mockAC), address(mockEC), owner);
        assertEq(noSupplyToken.totalSupply(), 0);
        assertEq(noSupplyToken.balanceOf(owner), 0);
    }

    function test_Initialize_Revert_ZeroAddresses() public {
        PREWAToken logic = new PREWAToken();
        TransparentProxy proxy;
        PREWAToken newToken;
        
        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "admin_"));
        newToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, 0, CAP, address(mockAC), address(mockEC), address(0));
        
        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(PREWA_ACZero.selector);
        newToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, 0, CAP, address(0), address(mockEC), owner);
        
        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(PREWA_ECZero.selector);
        newToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, 0, CAP, address(mockAC), address(0), owner);
    }
    
    function test_Initialize_Revert_InvalidMetadataOrDecimals() public {
        PREWAToken logic = new PREWAToken();
        TransparentProxy proxy;
        PREWAToken newToken;

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(PREWA_NameEmpty.selector);
        newToken.initialize("", TOKEN_SYMBOL, TOKEN_DECIMALS, 0, CAP, address(mockAC), address(mockEC), owner);
        
        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(PREWA_SymbolEmpty.selector);
        newToken.initialize(TOKEN_NAME, "", TOKEN_DECIMALS, 0, CAP, address(mockAC), address(mockEC), owner);

        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(PREWA_DecimalsZero.selector);
        newToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, 0, 0, CAP, address(mockAC), address(mockEC), owner);
        
        proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        newToken = PREWAToken(payable(address(proxy)));
        vm.expectRevert(PREWA_DecimalsZero.selector); 
        newToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, 19, 0, CAP, address(mockAC), address(mockEC), owner);
    }
    
    function test_Initialize_Revert_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(TOKEN_NAME,TOKEN_SYMBOL,TOKEN_DECIMALS,0,CAP,address(mockAC),address(mockEC),owner);
    }
    
    function test_Constructor_Runs() public {
        new PREWAToken();
        assertTrue(true, "Constructor ran");
    }

    function test_Transfer_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, false); 
        emit IERC20Upgradeable.Transfer(owner, user1, 100e18);
        assertTrue(token.transfer(user1, 100e18));
        assertEq(token.balanceOf(user1), 100e18);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100e18);
    }
    
    function test_Transfer_ZeroAmount() public {
        vm.prank(owner);
        assertTrue(token.transfer(user1, 0));
        assertEq(token.balanceOf(user1), 0);
    }

    function test_Transfer_Revert_Paused() public {
        vm.prank(pauserUser); token.pause();
        vm.prank(owner);
        vm.expectRevert("Pausable: paused");
        token.transfer(user1, 100e18);
    }
    function test_Transfer_Revert_SenderBlacklisted() public {
        vm.prank(owner); token.blacklist(owner);
        skip(token.getBlacklistTimelockDuration() + 1);
        vm.prank(owner); token.executeBlacklist(owner);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_SenderBlacklisted.selector, owner));
        token.transfer(user1, 100e18);
    }
    function test_Transfer_Revert_RecipientBlacklisted() public {
        vm.prank(owner); token.blacklist(user1);
        skip(token.getBlacklistTimelockDuration() + 1);
        vm.prank(owner); token.executeBlacklist(user1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_RecipientBlacklisted.selector, user1));
        token.transfer(user1, 100e18);
    }
    function test_Transfer_Revert_InsufficientBalance() public {
        vm.prank(user1); 
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 100e18));
        token.transfer(user2, 100e18);
    }
     function test_Transfer_Revert_FromZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientAllowance.selector, 0, 100e18));
        token.transferFrom(address(0), user1, 100e18);
    }
    function test_Transfer_Revert_ToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_TransferToZero.selector);
        token.transfer(address(0), 100e18);
    }

    function test_Approve_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit IERC20Upgradeable.Approval(owner, user1, 500e18);
        assertTrue(token.approve(user1, 500e18));
        assertEq(token.allowance(owner, user1), 500e18);
    }
    
    function test_Approve_SameValue_NoOp() public {
        vm.prank(owner);
        token.approve(user1, 500e18); 
        
        vm.prank(owner);
        assertTrue(token.approve(user1, 500e18));
        assertEq(token.allowance(owner, user1), 500e18);
    }
    function test_Approve_Revert_OwnerBlacklisted() public {
        vm.prank(owner); token.blacklist(owner);
        skip(token.getBlacklistTimelockDuration() + 1);
        vm.prank(owner); token.executeBlacklist(owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_OwnerBlacklisted.selector, owner));
        token.approve(user1, 100e18);
    }
    function test_Approve_Revert_SpenderBlacklisted() public {
        vm.prank(owner); token.blacklist(user1);
        skip(token.getBlacklistTimelockDuration() + 1);
        vm.prank(owner); token.executeBlacklist(user1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_SpenderBlacklisted.selector, user1));
        token.approve(user1, 100e18);
    }
    function test_Approve_Revert_OwnerOrSpenderZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "spenderApproval"));
        token.approve(address(0), 100e18);
    }

    function test_TransferFrom_Success() public {
        vm.prank(owner); token.approve(user1, 200e18); 
        
        vm.prank(user1); 
        vm.expectEmit(true, true, true, false); 
        emit IERC20Upgradeable.Transfer(owner, user2, 150e18);
        assertTrue(token.transferFrom(owner, user2, 150e18));
        
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 150e18);
        assertEq(token.balanceOf(user2), 150e18);
        assertEq(token.allowance(owner, user1), 50e18); 
    }
    
    function test_TransferFrom_Revert_InsufficientAllowance() public {
        vm.prank(owner); token.approve(user1, 100e18);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(InsufficientAllowance.selector, 100e18, 150e18));
        token.transferFrom(owner, user2, 150e18);
    }

    function test_Mint_Success() public {
        vm.prank(minterUser);
        uint256 mintAmount = 50e18;
        vm.expectEmit(true, true, true, false); 
        emit IERC20Upgradeable.Transfer(address(0), user1, mintAmount);
        assertTrue(token.mint(user1, mintAmount));
        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }
    function test_Mint_Revert_NotMinter() public {
        vm.prank(user1); 
        vm.expectRevert(PREWA_NotMinter.selector);
        token.mint(user2, 50e18);
    }
    function test_Mint_Revert_ToZeroOrBlacklistedOrZeroAmountOrCapExceeded() public {
        vm.prank(minterUser);
        vm.expectRevert(abi.encodeWithSelector(PREWA_MintToZero.selector));
        token.mint(address(0), 50e18);

        vm.prank(owner); token.blacklist(user1);
        skip(token.getBlacklistTimelockDuration() + 1);
        vm.prank(owner); token.executeBlacklist(user1);
        
        vm.prank(minterUser);
        vm.expectRevert(abi.encodeWithSelector(PREWA_RecipientBlacklisted.selector, user1));
        token.mint(user1, 50e18);
        vm.prank(owner); token.unblacklist(user1); 

        vm.prank(minterUser);
        vm.expectRevert(abi.encodeWithSelector(AmountIsZero.selector));
        token.mint(user1, 0);
        
        uint256 amountToExceedCap = CAP - INITIAL_SUPPLY + 1;
        vm.prank(minterUser);
        vm.expectRevert(abi.encodeWithSelector(CapExceeded.selector, INITIAL_SUPPLY, amountToExceedCap, CAP));
        token.mint(user1, amountToExceedCap);
    }

    function _add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function test_Mint_Success_NoCap() public {
        vm.prank(owner);
        token.setCap(0); 
        
        vm.prank(minterUser);
        uint256 mintAmount = 10_000_000e18;
        assertTrue(token.mint(user1, mintAmount));
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function test_Burn_Success() public {
        uint256 burnAmount = 50e18;
        vm.prank(owner);

        vm.expectEmit(true, true, true, false); 
        emit IERC20Upgradeable.Transfer(owner, address(0), burnAmount);
        assertTrue(token.burn(burnAmount));
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }
    
    function test_Burn_Revert_BurnFromZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientAllowance.selector, 0, 1e18));
        token.burnFrom(address(0), 1e18);
    }
    
    function test_Burn_Revert_AmountZero() public {
        vm.prank(owner);
        vm.expectRevert(AmountIsZero.selector);
        token.burn(0);
    }

    function test_BurnFrom_Success() public {
        uint256 burnAmount = 30e18;
        vm.prank(owner); token.approve(user1, 50e18); 

        vm.prank(user1); 
        vm.expectEmit(true, true, true, false);
        emit IERC20Upgradeable.Transfer(owner, address(0), burnAmount);
        assertTrue(token.burnFrom(owner, burnAmount));
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(token.allowance(owner, user1), 20e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }
    
    function test_BurnFrom_Success_MaxAllowance() public {
        uint256 burnAmount = 30e18;
        vm.prank(owner); token.approve(user1, type(uint256).max); 

        vm.prank(user1); 
        assertTrue(token.burnFrom(owner, burnAmount));
        assertEq(token.allowance(owner, user1), type(uint256).max);
    }

    function test_PauseUnpause_Success() public {
        assertFalse(token.paused());
        vm.prank(pauserUser);
        assertTrue(token.pause());
        assertTrue(token.paused());
        vm.prank(pauserUser);
        assertTrue(token.unpause());
        assertFalse(token.paused());
    }
    function test_PauseUnpause_Revert_NotPauser() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PREWA_MustHavePauserRole.selector));
        token.pause();
        
        vm.prank(pauserUser);
        token.pause();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(PREWA_MustHavePauserRole.selector));
        token.unpause();
    }
    
    function test_Pause_Revert_NotPauser_Owner() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_MustHavePauserRole.selector));
        token.pause();
    }

    function test_Blacklist_Instant_IfTimelockZero() public {
        vm.prank(owner);
        token.setBlacklistTimelockDuration(0); 
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IpREWAToken.BlacklistStatusChanged(user1, true, owner);
        assertTrue(token.blacklist(user1));
        assertTrue(token.isBlacklisted(user1));
    }
    function test_Blacklist_Propose_IfTimelockNonZero() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IpREWAToken.BlacklistProposed(user1, block.timestamp + 1 days, owner);
        assertTrue(token.blacklist(user1));
        assertFalse(token.isBlacklisted(user1)); 
        (bool exists, uint256 execAfter, ) = token.getBlacklistProposal(user1);
        assertTrue(exists);
        assertEq(execAfter, block.timestamp + 1 days);
    }
    function test_Blacklist_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_AccountBlacklistZero.selector);
        token.blacklist(address(0));

        vm.prank(owner);
        token.blacklist(user1); 
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_BlacklistPropExists.selector, user1));
        token.blacklist(user1); 

        vm.prank(owner);
        token.setBlacklistTimelockDuration(0);
        vm.prank(owner);
        token.blacklist(user2); 
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_AccountAlreadyBlacklisted.selector, user2));
        token.blacklist(user2); 
    }

    function test_ExecuteBlacklist_Success() public {
        vm.prank(owner);
        token.blacklist(user1); 
        skip(token.getBlacklistTimelockDuration() + 1); 
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IpREWAToken.BlacklistStatusChanged(user1, true, owner);
        assertTrue(token.executeBlacklist(user1));
        assertTrue(token.isBlacklisted(user1));
        (bool exists,,) = token.getBlacklistProposal(user1);
        assertFalse(exists, "Proposal should be cleared");
    }
    function test_ExecuteBlacklist_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_AccountBlacklistZero.selector);
        token.executeBlacklist(address(0));
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_NoBlacklistProp.selector, user1));
        token.executeBlacklist(user1); 
    
        vm.prank(owner);
        token.blacklist(user1); 
        vm.prank(owner);
        vm.expectRevert(PREWA_TimelockActive.selector);
        token.executeBlacklist(user1);
    }

    function test_CancelBlacklistProposal_Success() public {
        vm.prank(owner);
        token.blacklist(user1); 
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IpREWAToken.BlacklistCancelled(user1, owner);
        assertTrue(token.cancelBlacklistProposal(user1));
        (bool proposalExists,,) = token.getBlacklistProposal(user1); 
        assertFalse(proposalExists);
    }
    
    function test_CancelBlacklistProposal_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_AccountBlacklistZero.selector);
        token.cancelBlacklistProposal(address(0));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_NoBlacklistProp.selector, user1));
        token.cancelBlacklistProposal(user1);
    }

    function test_Unblacklist_Success() public {
        vm.prank(owner);
        token.setBlacklistTimelockDuration(0); 
        vm.prank(owner);
        token.blacklist(user1); 
        assertTrue(token.isBlacklisted(user1));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IpREWAToken.BlacklistStatusChanged(user1, false, owner);
        assertTrue(token.unblacklist(user1));
        assertFalse(token.isBlacklisted(user1));
    }
    function test_Unblacklist_ClearsProposalIfExists() public {
        vm.prank(owner);
        token.blacklist(user1); 
        (bool proposalExistsBefore,,) = token.getBlacklistProposal(user1); 
        assertTrue(proposalExistsBefore);
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true); 
        emit IpREWAToken.BlacklistCancelled(user1, owner);
        assertTrue(token.cancelBlacklistProposal(user1));

        (bool proposalExistsAfter,,) = token.getBlacklistProposal(user1); 
        assertFalse(proposalExistsAfter);
        assertFalse(token.isBlacklisted(user1));
    }
    
    function test_Unblacklist_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_AccountBlacklistZero.selector);
        token.unblacklist(address(0));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_AccountNotBlacklisted.selector, user1));
        token.unblacklist(user1);
    }

    function test_SetCap_Success() public {
        vm.prank(owner);
        uint256 newCap = CAP * 2;
        vm.expectEmit(true, false, false, true);
        emit IpREWAToken.CapUpdated(CAP, newCap, owner);
        assertTrue(token.setCap(newCap));
        assertEq(token.cap(), newCap);
    }
    function test_SetCap_Revert_LessThanSupply() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_CapLessThanSupply.selector, INITIAL_SUPPLY -1, INITIAL_SUPPLY));
        token.setCap(INITIAL_SUPPLY - 1);
    }
    function test_SetCap_ToZero_Success() public {
        vm.prank(owner);
        assertTrue(token.setCap(0)); 
        assertEq(token.cap(), 0);
    }

    function test_RecoverTokens_Success() public {
        MockERC20 otherToken = new MockERC20();
        otherToken.mockInitialize("Other","OTH",18,owner);
        vm.prank(owner);
        otherToken.mintForTest(address(token), 100e18);

        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit IpREWAToken.TokenRecovered(address(otherToken), 50e18, owner);
        assertTrue(token.recoverTokens(address(otherToken), 50e18));
        assertEq(otherToken.balanceOf(owner), 50e18);
    }
    
    function test_RecoverTokens_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_BadTokenRecoveryAddress.selector);
        token.recoverTokens(address(0), 10e18);
        vm.prank(owner);
        vm.expectRevert(PREWA_CannotRecoverSelf.selector);
        token.recoverTokens(address(token), 10e18);
        vm.prank(owner);
        vm.expectRevert(AmountIsZero.selector);
        token.recoverTokens(address(user1), 0);

        MockERC20 otherToken = new MockERC20(); 
        otherToken.mockInitialize("O","O",18,owner);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 10e18));
        token.recoverTokens(address(otherToken), 10e18);
    }

    function test_AddRemoveMinter_Success() public {
        address newMinter = makeAddr("newMinter");
        assertFalse(token.isMinter(newMinter));
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IpREWAToken.MinterStatusChanged(newMinter, true, owner);
        assertTrue(token.addMinter(newMinter));
        assertTrue(token.isMinter(newMinter));

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit IpREWAToken.MinterStatusChanged(newMinter, false, owner);
        assertTrue(token.removeMinter(newMinter));
        assertFalse(token.isMinter(newMinter));
    }
    
    function test_AddRemoveMinter_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(PREWA_MinterAddressZero.selector);
        token.addMinter(address(0));
        vm.prank(owner);
        vm.expectRevert(PREWA_MinterAddressZero.selector);
        token.removeMinter(address(0));
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_AddressAlreadyMinter.selector, minterUser));
        token.addMinter(minterUser);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_AddressNotMinter.selector, user2));
        token.removeMinter(user2);
    }

    function test_RenounceOwnership_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("pREWAToken: renounceOwnership is permanently disabled for security reasons");
        token.renounceOwnership();
    }
    
    function test_TransferTokenOwnership_Success() public {
        vm.prank(owner);
        assertTrue(token.transferTokenOwnership(user1));
        assertEq(token.owner(), user1);
    }

    function test_GetBlacklistProposal_And_SetTimelock_Coverage() public {
        vm.prank(owner);
        (bool exists, ,) = token.getBlacklistProposal(address(0));
        assertFalse(exists);

        vm.prank(owner);
        token.blacklist(user1);
        
        bool proposalExists;
        uint256 executeAfterTimestamp;
        uint256 timeRemainingSec;
        (proposalExists, executeAfterTimestamp, timeRemainingSec) = token.getBlacklistProposal(user1);

        assertTrue(proposalExists);
        assertTrue(executeAfterTimestamp > 0);
        assertTrue(timeRemainingSec > 0);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_TimelockDurationInvalid.selector, Constants.MIN_TIMELOCK_DURATION - 1));
        token.setBlacklistTimelockDuration(Constants.MIN_TIMELOCK_DURATION - 1);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PREWA_TimelockDurationInvalid.selector, Constants.MAX_TIMELOCK_DURATION + 1));
        token.setBlacklistTimelockDuration(Constants.MAX_TIMELOCK_DURATION + 1);
    }

    function test_PREWAToken_IsEmergencyPaused_Logic() public {
        assertFalse(token.isEmergencyPaused());
        assertFalse(token.paused()); 

        vm.prank(pauserUser); token.pause();
        assertTrue(token.isEmergencyPaused());
        assertTrue(token.paused());
        vm.prank(pauserUser); token.unpause();
        assertFalse(token.isEmergencyPaused());

        mockEC.setMockSystemPaused(true);
        assertTrue(token.isEmergencyPaused());
        assertTrue(token.paused()); 
        mockEC.setMockSystemPaused(false);
        assertFalse(token.isEmergencyPaused());

        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_CRITICAL);
        assertTrue(token.isEmergencyPaused());
        assertTrue(token.paused());
        mockEC.setMockEmergencyLevel(Constants.EMERGENCY_LEVEL_NORMAL);
        assertFalse(token.isEmergencyPaused());
    }
    
    function test_EmergencyShutdown_Success_PausesAtCritical() public {
        assertFalse(token.paused());
        vm.prank(address(mockEC)); 
        vm.expectEmit(true, true, true, false); 
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_CRITICAL, address(mockEC));
        assertTrue(token.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL));
        assertTrue(token.paused());
    }
    
    function test_EmergencyShutdown_Success_NoPauseBelowCritical() public {
        assertFalse(token.paused());
        vm.prank(address(mockEC));
        vm.expectEmit(true, true, true, false); 
        emit IEmergencyAware.EmergencyShutdownHandled(Constants.EMERGENCY_LEVEL_ALERT, address(mockEC));
        assertTrue(token.emergencyShutdown(Constants.EMERGENCY_LEVEL_ALERT));
        assertFalse(token.paused());
    }
    
    function test_EmergencyShutdown_Revert_CallerNotEC() public {
        vm.prank(owner); 
        vm.expectRevert(PREWA_CallerNotEmergencyController.selector);
        token.emergencyShutdown(Constants.EMERGENCY_LEVEL_CRITICAL);
    }
    
    function test_EmergencyShutdown_Revert_ECZero() public {
        PREWAToken logic = new PREWAToken();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        PREWAToken newToken = PREWAToken(payable(address(proxy)));
        
        vm.expectRevert(PREWA_ECZero.selector); 
        newToken.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, 0, CAP, address(mockAC), address(0), owner);
    }

    function test_SetEmergencyController_Success() public {
        MockEmergencyController newEc = new MockEmergencyController();
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit PREWAToken.EmergencyControllerSet(address(mockEC), address(newEc), owner);
        assertTrue(token.setEmergencyController(address(newEc)));
        assertEq(address(token.emergencyController()), address(newEc));
    }
     function test_SetEmergencyController_Revert_NotAContract() public {
        address nonContractAddr = makeAddr("nonContractForPREWAEC");
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "emergencyController"));
        token.setEmergencyController(nonContractAddr);
    }
}