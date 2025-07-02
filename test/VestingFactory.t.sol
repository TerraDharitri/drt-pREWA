// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/vesting/VestingFactory.sol";
import "../contracts/vesting/interfaces/IVestingFactory.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockVestingImplementation.sol";
import "../contracts/proxy/TransparentProxy.sol";
import "../contracts/libraries/Constants.sol";
import "../contracts/libraries/Errors.sol";

contract VestingFactoryTest is Test {
    VestingFactory factory;
    MockERC20 pREWAToken;
    MockVestingImplementation vestingLogic;

    address owner;
    address user1;
    address beneficiary;
    address proxyAdmin;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        beneficiary = makeAddr("beneficiary");
        proxyAdmin = makeAddr("proxyAdmin");

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, owner);

        vestingLogic = new MockVestingImplementation();

        VestingFactory logic = new VestingFactory();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        factory = VestingFactory(address(proxy));
        factory.initialize(owner, address(pREWAToken), address(vestingLogic), proxyAdmin);
        
        vm.prank(owner);
        pREWAToken.mintForTest(user1, 1_000_000 * 1e18);
        vm.prank(user1);
        pREWAToken.approve(address(factory), type(uint256).max);
    }

    function test_Initialize_Success() public view {
        assertEq(factory.owner(), owner);
        assertEq(factory.getTokenAddress(), address(pREWAToken));
        assertEq(factory.getImplementation(), address(vestingLogic));
        assertEq(factory.proxyAdminAddress(), proxyAdmin);
    }
    
    function test_Initialize_Reverts_ZeroAddresses() public {
        VestingFactory logic = new VestingFactory();
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        VestingFactory newFactory = VestingFactory(address(proxy));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner_"));
        newFactory.initialize(address(0), address(pREWAToken), address(vestingLogic), proxyAdmin);
    }

    function test_CreateVesting_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 duration = 365 days;
        uint256 cliff = 30 days;

        vm.startPrank(user1);
        // We can't predict the contract address, so we check for the event without the address.
        vm.expectEmit(false, true, true, true);
        emit IVestingFactory.VestingCreated(address(0), beneficiary, amount, user1);
        
        address vestingAddress = factory.createVesting(beneficiary, 0, cliff, duration, true, amount);
        
        assertTrue(vestingAddress != address(0));
        assertEq(pREWAToken.balanceOf(vestingAddress), amount);

        address[] memory byBen = factory.getVestingsByBeneficiary(beneficiary);
        assertEq(byBen.length, 1);
        assertEq(byBen[0], vestingAddress);
        
        address[] memory byOwner = factory.getVestingsByOwner(user1);
        assertEq(byOwner.length, 1);
        assertEq(byOwner[0], vestingAddress);
        vm.stopPrank();
    }

    function test_CreateVesting_Reverts() public {
        vm.prank(user1);
        vm.expectRevert(Vesting_BeneficiaryZero.selector);
        factory.createVesting(address(0), 0, 30 days, 365 days, true, 1e18);
        
        vm.prank(user1);
        vm.expectRevert(Vesting_AmountZeroV.selector);
        factory.createVesting(beneficiary, 0, 30 days, 365 days, true, 0);

        vm.prank(user1);
        vm.expectRevert(Vesting_DurationZero.selector);
        factory.createVesting(beneficiary, 0, 0, 0, true, 1e18);
    }
    
    function test_Getters_Paginated() public {
        vm.startPrank(user1);
        factory.createVesting(beneficiary, 0, 1, 30 days, true, 1e18);
        factory.createVesting(beneficiary, 0, 1, 30 days, true, 2e18);
        factory.createVesting(makeAddr("ben2"), 0, 1, 30 days, true, 3e18);
        vm.stopPrank();

        (address[] memory page1, uint256 total1) = factory.getVestingsByBeneficiaryPaginated(beneficiary, 0, 1);
        assertEq(total1, 2);
        assertEq(page1.length, 1);
        
        (address[] memory page2, uint256 total2) = factory.getVestingsByOwnerPaginated(user1, 1, 5);
        assertEq(total2, 3);
        assertEq(page2.length, 2);
        
        (address[] memory page3, uint256 total3) = factory.getAllVestingContractsPaginated(0, 10);
        assertEq(total3, 3);
        assertEq(page3.length, 3);
    }
    
    function test_SetImplementation_Success() public {
        MockVestingImplementation newImpl = new MockVestingImplementation();
        vm.prank(owner);
        assertTrue(factory.setImplementation(address(newImpl)));
        assertEq(factory.getImplementation(), address(newImpl));
    }

    function test_SetImplementation_Revert_NotOwnerOrNotContract() public {
        MockVestingImplementation newImpl = new MockVestingImplementation();
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setImplementation(address(newImpl));
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "newVestingImplementation"));
        factory.setImplementation(makeAddr("notAContract"));
    }
}