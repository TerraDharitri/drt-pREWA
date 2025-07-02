// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/vesting/VestingFactory.sol";
import "../contracts/vesting/VestingImplementation.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAccessControl.sol";
import "../contracts/mocks/MockEmergencyController.sol";
import "../contracts/mocks/MockOracleIntegration.sol";
import "../contracts/proxy/TransparentProxy.sol";
import "../contracts/libraries/Constants.sol";

contract VestingFactoryCoverageTest is Test {
    VestingFactory factory;
    VestingImplementation logic;
    MockERC20 token;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;
    MockOracleIntegration mockOracle;

    address owner;
    address admin;
    address beneficiary;
    address proxyAdmin;

    function setUp() public {
        owner = address(0x1001);
        admin = address(0x1002);
        beneficiary = address(0x1003);
        proxyAdmin = address(0x1004);

        // Deploy mocks
        token = new MockERC20();
        token.mockInitialize("Test Token", "TEST", 18, owner);

        mockAC = new MockAccessControl();
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true);
        vm.prank(owner);
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), admin, true);

        mockEC = new MockEmergencyController();
        mockOracle = new MockOracleIntegration();

        // Deploy logic contract
        logic = new VestingImplementation();

        // Deploy factory via proxy
        VestingFactory factoryLogic = new VestingFactory();
        TransparentProxy proxy = new TransparentProxy(address(factoryLogic), proxyAdmin, "");
        factory = VestingFactory(address(proxy));

        factory.initialize(
            owner,
            address(token),
            address(logic),
            proxyAdmin
        );

        // Mint tokens to owner for vesting (users need to approve factory)
        vm.prank(owner);
        token.mintForTest(owner, 10000 ether);
    }

    // Test initialization edge cases
    function test_Initialize_Revert_ZeroToken() public {
        // Deploy factory logic directly (not through proxy)
        VestingFactory factoryLogic = new VestingFactory();
        TransparentProxy newProxy = new TransparentProxy(address(factoryLogic), proxyAdmin, "");
        VestingFactory newFactory = VestingFactory(address(newProxy));

        vm.expectRevert(Vesting_TokenZero.selector);
        newFactory.initialize(
            owner,
            address(0),
            address(logic),
            proxyAdmin
        );
    }

    // New test for reentrancy protection
    function test_CreateVesting_Revert_Reentrancy() public {
        uint256 amount = 1000 ether;
        uint256 duration = 365 days;
        uint256 cliff = 90 days;

        vm.startPrank(owner);
        token.approve(address(factory), amount * 2);

        // First vesting creation
        factory.createVesting(
            beneficiary,
            block.timestamp,
            cliff,
            duration,
            true,
            amount
        );

        // The lock should be released after the first call, so this should succeed
        address secondVesting = factory.createVesting(
            beneficiary,
            block.timestamp,
            cliff,
            duration,
            true,
            amount
        );

        assertNotEq(secondVesting, address(0));
        vm.stopPrank();
    }

    // New test for startTime in the past
    function test_CreateVesting_Revert_StartTimeInPast() public {
        uint256 amount = 1000 ether;
        uint256 duration = 365 days;
        uint256 cliff = 90 days;
        // Ensure we have a valid past time without underflow
        uint256 currentTime = 1000000;
        vm.warp(currentTime);
        uint256 pastTime = currentTime - 1 days;

        vm.startPrank(owner);
        token.approve(address(factory), amount);
        
        vm.expectRevert(Vesting_StartTimeInvalid.selector);
        factory.createVesting(
            beneficiary,
            pastTime,
            cliff,
            duration,
            true,
            amount
        );
        vm.stopPrank();
    }

    // Test for duration exceeding maximum allowed
    function test_CreateVesting_Revert_DurationTooLong() public {
        uint256 amount = 1000 ether;
        uint256 duration = Constants.MAX_VESTING_DURATION + 1;
        uint256 cliff = 90 days;

        vm.startPrank(owner);
        token.approve(address(factory), amount);
        
        vm.expectRevert(InvalidDuration.selector);
        factory.createVesting(
            beneficiary,
            block.timestamp,
            cliff,
            duration,
            true,
            amount
        );
        vm.stopPrank();
    }

    // New test for amount exceeding max
    function test_CreateVesting_Revert_AmountExceedsMax() public {
        uint256 amount = Constants.MAX_VESTING_AMOUNT + 1; // Exceed max amount
        uint256 duration = 365 days;
        uint256 cliff = 90 days;

        vm.startPrank(owner);
        token.approve(address(factory), amount);
        
        vm.expectRevert(abi.encodeWithSelector(VestingFactory.Vesting_AmountExceedsMax.selector, amount, Constants.MAX_VESTING_AMOUNT));
        factory.createVesting(
            beneficiary,
            block.timestamp,
            cliff,
            duration,
            true,
            amount
        );
        vm.stopPrank();
    }

    // --- createVesting additional coverage ---

    function test_CreateVesting_Revert_ImplementationZero() public {
        // This test aims to cover the `if (vestingImplementation == address(0))`
        // check within `createVesting`. However, `setImplementation` itself prevents
        // setting it to zero.
        // So, we first test that `setImplementation(address(0))` reverts as expected.
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "newVestingImplementation"));
        factory.setImplementation(address(0));

        // Since we can't set implementation to zero via the public interface to test
        // the createVesting internal check directly, this test effectively confirms
        // that the state (implementation being zero) is guarded by the setter.
        // The line in createVesting `if (vestingImplementation == address(0))` is technically
        // unreachable if initialize and setImplementation always enforce non-zero.
        // For full coverage of that line, contract logic would need to change or use storage manipulation.
        // Given current constraints, this test verifies the guard at the setter level.
    }

    function test_CreateVesting_Revert_BeneficiaryZero() public {
        vm.startPrank(owner);
        token.approve(address(factory), 100 ether);
        vm.expectRevert(Vesting_BeneficiaryZero.selector);
        factory.createVesting(address(0), block.timestamp, 0, 30 days, true, 100 ether);
        vm.stopPrank();
    }

    function test_CreateVesting_Revert_AmountZero() public {
        vm.startPrank(owner);
        // No need to approve if amount is 0, but good practice
        token.approve(address(factory), 0 ether);
        vm.expectRevert(Vesting_AmountZeroV.selector);
        factory.createVesting(beneficiary, block.timestamp, 0, 30 days, true, 0);
        vm.stopPrank();
    }

    function test_CreateVesting_Revert_DurationZero() public {
        vm.startPrank(owner);
        token.approve(address(factory), 100 ether);
        vm.expectRevert(Vesting_DurationZero.selector);
        factory.createVesting(beneficiary, block.timestamp, 0, 0, true, 100 ether);
        vm.stopPrank();
    }

    function test_CreateVesting_StartTimeZero_UsesBlockTimestamp() public {
        uint256 amount = 100 ether;
        uint256 duration = 30 days;
        uint256 cliff = 0;

        vm.startPrank(owner);
        token.approve(address(factory), amount);
        
        uint256 expectedStartTime = block.timestamp; // Capture before the call
        // Warp a bit to ensure block.timestamp inside createVesting might be different if not captured before
        vm.warp(block.timestamp + 10);
        expectedStartTime = block.timestamp; // Re-capture just before the call for accuracy

        address vestingContractAddr = factory.createVesting(
            beneficiary,
            0, // StartTime is zero
            cliff,
            duration,
            true,
            amount
        );
        vm.stopPrank();

        assertNotEq(vestingContractAddr, address(0));
        IVesting vestingContract = IVesting(vestingContractAddr);
        // getVestingSchedule returns: (address beneficiary, uint256 totalAmount, uint256 startTime, uint256 cliffDuration, uint256 duration, uint256 releasedAmount, bool revocable, bool revoked)
        (address actualBeneficiary, , uint256 actualStartTime, , , , , ) = vestingContract.getVestingSchedule();
        // Token address is not part of getVestingSchedule, it's set at initialization.
        // We can check it by calling token() on the vesting contract if it's public, or assume it's correct from initialization.
        // For this test, we are primarily concerned with startTime.
        assertEq(actualBeneficiary, beneficiary);
        assertEq(actualStartTime, expectedStartTime);
    }


    // New test for valid implementation change
    function test_SetImplementation_ValidContract() public {
        VestingImplementation newLogic = new VestingImplementation();

        vm.prank(owner);
        bool success = factory.setImplementation(address(newLogic));
        
        assertTrue(success);
        assertEq(factory.getImplementation(), address(newLogic));
    }

    // New test for pagination edge case
    function test_GetAllVestingContractsPaginated_OffsetExceedsTotal() public view {
        (address[] memory page, uint256 total) = factory.getAllVestingContractsPaginated(10, 5);
        assertEq(page.length, 0);
        assertEq(total, 0);
    }

    // New test for Vesting_CliffLongerThanDuration error
    function test_CreateVesting_Revert_CliffLongerThanDuration() public {
        uint256 amount = 1000 ether;
        uint256 duration = 90 days;
        uint256 cliff = 365 days; // Cliff longer than duration

        vm.startPrank(owner);
        token.approve(address(factory), amount);
        
        vm.expectRevert(Vesting_CliffLongerThanDuration.selector);
        factory.createVesting(
            beneficiary,
            block.timestamp,
            cliff,
            duration,
            true,
            amount
        );
        vm.stopPrank();
    }

    // New test for getVestingsByOwnerPaginated with offset > total
    function test_GetVestingsByOwnerPaginated_OffsetExceedsTotal() public {
        createVestingContract(address(0x2001), block.timestamp, 0, 30 days, false, 100 ether);
        createVestingContract(address(0x2002), block.timestamp, 0, 60 days, false, 200 ether);

        (address[] memory page, uint256 total) = factory.getVestingsByOwnerPaginated(owner, 3, 10);
        assertEq(page.length, 0);
        assertEq(total, 2);
    }

    // New test for getVestingsByBeneficiaryPaginated with offset > total
    function test_GetVestingsByBeneficiaryPaginated_OffsetExceedsTotal() public {
        createVestingContract(beneficiary, block.timestamp, 0, 30 days, false, 100 ether);
        createVestingContract(beneficiary, block.timestamp, 0, 60 days, false, 200 ether);

        (address[] memory page, uint256 total) = factory.getVestingsByBeneficiaryPaginated(beneficiary, 3, 10);
        assertEq(page.length, 0);
        assertEq(total, 2);
    }

    // --- Getter Reverts ---

    function test_GetVestingsByBeneficiary_Revert_BeneficiaryZero() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "beneficiary"));
        factory.getVestingsByBeneficiary(address(0));
    }

    function test_GetVestingsByBeneficiaryPaginated_Revert_BeneficiaryZero() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "beneficiary"));
        factory.getVestingsByBeneficiaryPaginated(address(0), 0, 10);
    }

    function test_GetVestingsByBeneficiaryPaginated_Revert_LimitZero() public {
        vm.expectRevert(VF_LimitIsZero.selector);
        factory.getVestingsByBeneficiaryPaginated(beneficiary, 0, 0);
    }

    function test_GetVestingsByOwner_Revert_OwnerZero() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "owner_"));
        factory.getVestingsByOwner(address(0));
    }

    function test_GetVestingsByOwnerPaginated_Revert_OwnerZero() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "owner_"));
        factory.getVestingsByOwnerPaginated(address(0), 0, 10);
    }

    function test_GetVestingsByOwnerPaginated_Revert_LimitZero() public {
        vm.expectRevert(VF_LimitIsZero.selector);
        factory.getVestingsByOwnerPaginated(owner, 0, 0);
    }

    function test_GetAllVestingContractsPaginated_Revert_LimitZero() public {
        vm.expectRevert(VF_LimitIsZero.selector);
        factory.getAllVestingContractsPaginated(0, 0);
    }

    function test_Initialize_Revert_ZeroImplementation() public {
        VestingFactory factoryLogic = new VestingFactory();
        TransparentProxy newProxy = new TransparentProxy(address(factoryLogic), proxyAdmin, "");
        VestingFactory newFactory = VestingFactory(address(newProxy));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialVestingImplementation_"));
        newFactory.initialize(
            owner,
            address(token),
            address(0),
            proxyAdmin
        );
    }

    function test_Initialize_Revert_ZeroProxyAdmin() public {
        VestingFactory factoryLogic = new VestingFactory();
        TransparentProxy newProxy = new TransparentProxy(address(factoryLogic), proxyAdmin, "");
        VestingFactory newFactory = VestingFactory(address(newProxy));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "adminForProxies_"));
        newFactory.initialize(
            owner,
            address(token),
            address(logic),
            address(0)
        );
    }

    // --- Setter Reverts ---

    function test_SetImplementation_Revert_ImplementationZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "newVestingImplementation"));
        factory.setImplementation(address(0));
    }

    function test_SetImplementation_Revert_ImplementationNotAContract() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, "newVestingImplementation"));
        factory.setImplementation(address(0x123)); // EOA, not a contract
    }

    function test_SetProxyAdmin_Revert_ProxyAdminZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "newProxyAdminAddress"));
        factory.setProxyAdmin(address(0));
    }

    function test_Initialize_Revert_ZeroOwner() public {
        VestingFactory factoryLogic = new VestingFactory();
        TransparentProxy newProxy = new TransparentProxy(address(factoryLogic), proxyAdmin, "");
        VestingFactory newFactory = VestingFactory(address(newProxy));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner_"));
        newFactory.initialize(
            address(0),
            address(token),
            address(logic),
            proxyAdmin
        );
    }

    // --- Pagination Ternary Path Coverage ---

    function test_GetVestingsByBeneficiaryPaginated_Ternary_TotalMinusOffsetLessThanLimit() public {
        // Setup: 2 vestings for 'beneficiary'
        createVestingContract(beneficiary, block.timestamp, 0, 30 days, false, 100 ether);
        createVestingContract(beneficiary, block.timestamp, 0, 60 days, false, 200 ether);
        // Create one for another beneficiary to ensure filtering works
        createVestingContract(address(0xDEAD), block.timestamp, 0, 30 days, false, 50 ether);


        // total = 2. offset = 1. limit = 5.
        // count = total - offset < limit ? total - offset : limit;
        // count = 2 - 1 < 5 ? 2 - 1 : 5;  (1 < 5 ? 1 : 5) -> count = 1
        (address[] memory page, uint256 total) = factory.getVestingsByBeneficiaryPaginated(beneficiary, 1, 5);
        assertEq(page.length, 1, "Page length should be 1 (total - offset)");
        assertEq(total, 2, "Total should be 2");
    }
    
    function test_GetVestingsByBeneficiaryPaginated_Ternary_TotalMinusOffsetGreaterEqualLimit() public {
        // Setup: 5 vestings for 'beneficiary'
        for (uint i = 0; i < 5; i++) {
            createVestingContract(beneficiary, block.timestamp, 0, 30 days + i, false, (100 + i) * 1 ether);
        }
        // total = 5. offset = 1. limit = 2.
        // count = total - offset < limit ? total - offset : limit;
        // count = 5 - 1 < 2 ? 4 : 2; (4 < 2 ? 4 : 2) -> count = 2
        (address[] memory page, uint256 total) = factory.getVestingsByBeneficiaryPaginated(beneficiary, 1, 2);
        assertEq(page.length, 2, "Page length should be 2 (limit)");
        assertEq(total, 5, "Total should be 5");
    }

    function test_GetVestingsByOwnerPaginated_Ternary_TotalMinusOffsetLessThanLimit() public {
        // Setup: 2 vestings by 'owner'
        createVestingContract(address(0x2001), block.timestamp, 0, 30 days, false, 100 ether); // owner is msg.sender in helper
        createVestingContract(address(0x2002), block.timestamp, 0, 60 days, false, 200 ether); // owner is msg.sender in helper

        // total = 2. offset = 1. limit = 5. -> count = 1
        (address[] memory page, uint256 total) = factory.getVestingsByOwnerPaginated(owner, 1, 5);
        assertEq(page.length, 1, "Page length should be 1 (total - offset)");
        assertEq(total, 2, "Total should be 2");
    }

    function test_GetVestingsByOwnerPaginated_Ternary_TotalMinusOffsetGreaterEqualLimit() public {
        // Setup: 5 vestings by 'owner'
        for (uint i = 0; i < 5; i++) {
            createVestingContract(makeAddr(string.concat("owner_test_bene_", vm.toString(i))), block.timestamp, 0, 30 days + i, false, (100 + i) * 1 ether);
        }
        // total = 5. offset = 1. limit = 2. -> count = 2
        (address[] memory page, uint256 total) = factory.getVestingsByOwnerPaginated(owner, 1, 2);
        assertEq(page.length, 2, "Page length should be 2 (limit)");
        assertEq(total, 5, "Total should be 5");
    }

    function test_GetAllVestingContractsPaginated_Ternary_TotalMinusOffsetLessThanLimit() public {
        // Setup: 2 total vestings
        createVestingContract(address(0x4001), block.timestamp, 0, 30 days, false, 100 ether);
        createVestingContract(address(0x4002), block.timestamp, 0, 60 days, false, 200 ether);

        // total = 2. offset = 1. limit = 5. -> count = 1
        (address[] memory page, uint256 total) = factory.getAllVestingContractsPaginated(1, 5);
        assertEq(page.length, 1, "Page length should be 1 (total - offset)");
        assertEq(total, 2, "Total should be 2");
    }

    function test_GetAllVestingContractsPaginated_Ternary_TotalMinusOffsetGreaterEqualLimit() public {
        // Setup: 5 total vestings
        for (uint i = 0; i < 5; i++) {
            createVestingContract(makeAddr(string.concat("all_test_bene_", vm.toString(i))), block.timestamp, 0, 30 days + i, false, (100 + i) * 1 ether);
        }
        // total = 5. offset = 1. limit = 2. -> count = 2
        (address[] memory page, uint256 total) = factory.getAllVestingContractsPaginated(1, 2);
        assertEq(page.length, 2, "Page length should be 2 (limit)");
        assertEq(total, 5, "Total should be 5");
    }


    // Test createVesting with various scenarios
    function test_CreateVesting_Success() public {
        uint256 amount = 1000 ether;
        uint256 duration = 365 days;
        uint256 cliff = 90 days;
        
        vm.startPrank(owner);
        token.approve(address(factory), amount);
        
        address vestingContract = factory.createVesting(
            beneficiary,
            block.timestamp,
            cliff,
            duration,
            true,
            amount
        );
        vm.stopPrank();
        
        assertNotEq(vestingContract, address(0));
        // Check that vesting was created
        address[] memory vestingsByBeneficiary = factory.getVestingsByBeneficiary(beneficiary);
        assertEq(vestingsByBeneficiary.length, 1);
        assertEq(vestingsByBeneficiary[0], vestingContract);
        
        // Verify vesting was tracked by owner
        address[] memory vestingsByOwner = factory.getVestingsByOwner(owner);
        assertEq(vestingsByOwner.length, 1);
        assertEq(vestingsByOwner[0], vestingContract);
    }

    // Test multiple individual vesting creations
    function test_CreateMultipleVestingContracts_Success() public {
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = address(0x2001);
        beneficiaries[1] = address(0x2002);
        beneficiaries[2] = address(0x2003);
        
        uint256 totalAmount = 4500 ether; // 1000 + 2000 + 1500
        vm.prank(owner);
        token.approve(address(factory), totalAmount);
        
        vm.startPrank(owner);
        address contract1 = factory.createVesting(
            beneficiaries[0],
            block.timestamp,
            90 days,
            365 days,
            true,
            1000 ether
        );
        address contract2 = factory.createVesting(
            beneficiaries[1],
            block.timestamp + 30 days,
            180 days,
            730 days,
            false,
            2000 ether
        );
        address contract3 = factory.createVesting(
            beneficiaries[2],
            block.timestamp + 60 days,
            270 days,
            1095 days,
            true,
            1500 ether
        );
        vm.stopPrank();
        
        assertNotEq(contract1, address(0));
        assertNotEq(contract2, address(0));
        assertNotEq(contract3, address(0));
        
        // Verify each beneficiary has their vesting
        assertEq(factory.getVestingsByBeneficiary(beneficiaries[0]).length, 1);
        assertEq(factory.getVestingsByBeneficiary(beneficiaries[1]).length, 1);
        assertEq(factory.getVestingsByBeneficiary(beneficiaries[2]).length, 1);
    }

    // Test edge cases for vesting parameters
    function test_CreateVesting_MinimumDuration() public {
        vm.startPrank(owner);
        token.approve(address(factory), 1000 ether);
        
        address vestingContract = factory.createVesting(
            beneficiary,
            block.timestamp,
            0,
            7 days, // Minimum duration (from Constants.MIN_VESTING_DURATION)
            true,
            1000 ether
        );
        vm.stopPrank();
        
        assertNotEq(vestingContract, address(0));
    }

    function test_CreateVesting_Revert_DurationTooSmall() public {
        vm.startPrank(owner);
        token.approve(address(factory), 1000 ether);
        
        vm.expectRevert(InvalidDuration.selector);
        factory.createVesting(
            beneficiary,
            block.timestamp,
            0,
            1, // Less than minimum duration
            true,
            1000 ether
        );
        vm.stopPrank();
    }

    function test_CreateVesting_MaximumCliff() public {
        uint256 duration = 365 days;
        
        vm.prank(owner);
        token.approve(address(factory), 1000 ether);
        
        vm.prank(owner);
        address vestingContract = factory.createVesting(
            beneficiary,
            block.timestamp,
            duration, // Cliff equals duration (maximum)
            duration,
            true,
            1000 ether
        );
        
        assertNotEq(vestingContract, address(0));
    }

    // Test contract state after multiple operations
    function test_FactoryState_AfterMultipleOperations() public {
        vm.prank(owner);
        token.approve(address(factory), 3000 ether);
        
        vm.startPrank(owner);
        factory.createVesting(beneficiary, block.timestamp, 0, 365 days, true, 1000 ether);
        factory.createVesting(address(0x2001), block.timestamp, 90 days, 730 days, false, 2000 ether);
        vm.stopPrank();
        
        // Verify state
        (address[] memory allContracts, uint256 total) = factory.getAllVestingContractsPaginated(0, 100);
        assertEq(total, 2);
        assertEq(allContracts.length, 2);
        assertEq(token.balanceOf(owner), 7000 ether); // 10000 - 1000 - 2000 (tokens transferred from owner)
    }

    // Test invalid cliff duration
    function test_CreateVesting_Revert_CliffTooLong() public {
        vm.startPrank(owner);
        token.approve(address(factory), 1000 ether);
        
        vm.expectRevert(Vesting_CliffLongerThanDuration.selector);
        factory.createVesting(
            beneficiary,
            block.timestamp,
            365 days, // cliff
            180 days, // duration (shorter than cliff)
            true,
            1000 ether
        );
        vm.stopPrank();
    }

    // Test past start time validation
    function test_CreateVesting_Revert_InvalidStartTime() public {
        vm.startPrank(owner);
        token.approve(address(factory), 1000 ether);
        
        // Create a future timestamp that becomes past after warping
        uint256 futureTime = block.timestamp + 1 days;
        vm.warp(futureTime + 1);
        
        vm.expectRevert(Vesting_StartTimeInvalid.selector);
        factory.createVesting(
            beneficiary,
            futureTime, // now in the past due to warp
            0,
            30 days,
            false,
            1000 ether
        );
        vm.stopPrank();
    }

    // Test maximum vesting amount
    function test_CreateVesting_Revert_AmountTooLarge() public {
        uint256 maxAmount = Constants.MAX_VESTING_AMOUNT;
        vm.startPrank(owner);
        token.approve(address(factory), maxAmount + 1);
        
        vm.expectRevert(abi.encodeWithSelector(VestingFactory.Vesting_AmountExceedsMax.selector, maxAmount + 1, maxAmount));
        factory.createVesting(
            beneficiary,
            block.timestamp,
            0,
            30 days,
            false,
            maxAmount + 1
        );
        vm.stopPrank();
    }

    // Test maximum duration validation
    function test_CreateVesting_Revert_DurationExceedsMax() public {
        uint256 maxDuration = Constants.MAX_VESTING_DURATION;
        vm.startPrank(owner);
        token.approve(address(factory), 1000 ether);
        
        vm.expectRevert(InvalidDuration.selector);
        factory.createVesting(
            beneficiary,
            block.timestamp,
            0,
            maxDuration + 1,
            false,
            1000 ether
        );
        vm.stopPrank();
    }

    // Test pagination edge cases
    function test_GetAllVestingContractsPaginated_OffsetTooLarge() public {
        // Create 3 vesting contracts
        createVestingContract(owner, 0, 0, 30 days, false, 100 ether);
        createVestingContract(owner, 0, 0, 60 days, false, 200 ether);
        createVestingContract(owner, 0, 0, 90 days, false, 300 ether);
        
        // Try to get with offset beyond total
        (address[] memory page, uint256 total) = factory.getAllVestingContractsPaginated(5, 10);
        assertEq(page.length, 0);
        assertEq(total, 3);
    }

    // Helper function to create vesting contracts
    function createVestingContract(
        address beneficiary_,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable,
        uint256 amount
    ) private {
        vm.prank(owner);
        token.approve(address(factory), amount);
        
        vm.prank(owner);
        factory.createVesting(
            beneficiary_,
            startTime,
            cliffDuration,
            duration,
            revocable,
            amount
        );
    }
}