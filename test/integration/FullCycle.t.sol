// test/integration/FullCycle.t.sol

// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../contracts/vesting/VestingFactory.sol";
import "../../contracts/vesting/VestingImplementation.sol";
import "../../contracts/core/TokenStaking.sol";
import "../../contracts/proxy/TransparentProxy.sol";
import "../../contracts/vesting/interfaces/IVesting.sol";
import "../../contracts/mocks/MockERC20.sol";
import "../../contracts/mocks/MockAccessControl.sol";
import "../../contracts/mocks/MockEmergencyController.sol";
import "../../contracts/libraries/Constants.sol";

contract FullCycleTest is Test {
    VestingFactory vestingFactory;
    TokenStaking tokenStaking;
    MockERC20 pREWAToken;
    MockAccessControl mockAC;
    MockEmergencyController mockEC;

    address deployer;
    address beneficiary;
    address proxyAdmin;

    function setUp() public {
        deployer = address(this);
        beneficiary = makeAddr("beneficiary");
        proxyAdmin = makeAddr("proxyAdmin");

        pREWAToken = new MockERC20();
        pREWAToken.mockInitialize("pREWA Token", "PREWA", 18, deployer);
        
        mockAC = new MockAccessControl();
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), deployer, true);
        mockAC.setRole(mockAC.PARAMETER_ROLE(), deployer, true);
        
        mockEC = new MockEmergencyController();

        VestingImplementation vestingLogic = new VestingImplementation();
        VestingFactory factoryLogic = new VestingFactory();
        TransparentProxy factoryProxy = new TransparentProxy(address(factoryLogic), proxyAdmin, "");
        vestingFactory = VestingFactory(address(factoryProxy));
        vestingFactory.initialize(deployer, address(pREWAToken), address(vestingLogic), proxyAdmin);

        TokenStaking stakingLogic = new TokenStaking();
        TransparentProxy stakingProxy = new TransparentProxy(address(stakingLogic), proxyAdmin, "");
        tokenStaking = TokenStaking(payable(address(stakingProxy)));
        tokenStaking.initialize(
            address(pREWAToken),
            address(mockAC),
            address(mockEC),
            address(0),
            1000,
            1 days,
            deployer,
            10
        );
        tokenStaking.addTier(365 days, 10000, 2000);
        
        pREWAToken.mintForTest(address(tokenStaking), 1_000_000e18);
        pREWAToken.mintForTest(deployer, 1_000_000e18);
    }

    function test_VestingToStaking_FullCycle() public {
        uint256 vestingAmount = 1000e18;
        
        pREWAToken.approve(address(vestingFactory), vestingAmount);
        
        address vestingContractAddr = vestingFactory.createVesting(beneficiary, 0, 30 days, 365 days, false, vestingAmount);
        IVesting vestingContract = IVesting(vestingContractAddr);
        
        skip(90 days);
        
        uint256 releasable = vestingContract.releasableAmount();
        assertTrue(releasable > 0);
        vm.prank(beneficiary);
        vestingContract.release();
        assertEq(pREWAToken.balanceOf(beneficiary), releasable);
        
        // <<< FIX: The beneficiary must approve the tokenStaking contract to spend its tokens. >>>
        vm.prank(beneficiary);
        pREWAToken.approve(address(tokenStaking), releasable);

        vm.prank(beneficiary);
        uint256 positionId = tokenStaking.stake(releasable, 0);
        
        (uint256 stakedAmt,,,,,) = tokenStaking.getStakingPosition(beneficiary, positionId);
        assertEq(stakedAmt, releasable);
        assertEq(tokenStaking.totalStaked(), releasable);
    }
}