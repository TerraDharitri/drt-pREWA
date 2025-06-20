// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol"; 
import "../vesting/interfaces/IVesting.sol";
import "../interfaces/IEmergencyAware.sol";
import "../controllers/EmergencyController.sol";
import "../oracle/OracleIntegration.sol";
import "../libraries/Constants.sol"; 
import "../libraries/Errors.sol";   

contract MockVestingImplementation is Initializable, IVesting {
    address public mockAdmin; 

    struct VestingScheduleData {
        address beneficiary;
        uint256 totalAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 duration;
        uint256 releasedAmount;
        bool revocable;
        bool revoked;
        address scheduleOwner; 
    }
    VestingScheduleData public mockScheduleData;

    bool public mockIsEmergencyPausedState;
    address public mockEcAddress_State; 
    address public mockOracleAddress_State; 

    bool public initialized8Args;
    bool public initialized10Args;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }

    function setMockAdmin(address _admin) public {
        mockAdmin = _admin;
    }

    function initialize(
        address,
        address beneficiaryAddress_,
        uint256 startTimeValue_,
        uint256 cliffDurationValue_,
        uint256 durationValue_,
        bool isRevocable_,
        uint256 totalVestingAmount_,
        address initialOwnerAddress_
    ) public virtual override initializer {
        mockScheduleData = VestingScheduleData({
            beneficiary: beneficiaryAddress_,
            totalAmount: totalVestingAmount_,
            startTime: startTimeValue_ == 0 ? block.timestamp : startTimeValue_,
            cliffDuration: cliffDurationValue_,
            duration: durationValue_,
            releasedAmount: 0,
            revocable: isRevocable_,
            revoked: false,
            scheduleOwner: initialOwnerAddress_
        });
        initialized8Args = true;
    }

    function initialize(
        address,
        address beneficiaryAddress_,
        uint256 startTimeValue_,
        uint256 cliffDurationValue_,
        uint256 durationValue_,
        bool isRevocable_,
        uint256 totalVestingAmount_,
        address initialOwnerAddress_,
        address emergencyControllerAddress_,
        address oracleIntegrationAddress_
    ) public virtual override initializer {
         mockScheduleData = VestingScheduleData({
            beneficiary: beneficiaryAddress_,
            totalAmount: totalVestingAmount_,
            startTime: startTimeValue_ == 0 ? block.timestamp : startTimeValue_,
            cliffDuration: cliffDurationValue_,
            duration: durationValue_,
            releasedAmount: 0,
            revocable: isRevocable_,
            revoked: false,
            scheduleOwner: initialOwnerAddress_
        });
        mockEcAddress_State = emergencyControllerAddress_;
        mockOracleAddress_State = oracleIntegrationAddress_;
        initialized10Args = true;
    }

    function release() external override returns (uint256 amount) {
        require(!mockIsEmergencyPausedState, "MockVI: Paused");
        require(!mockScheduleData.revoked, "MockVI: Already revoked");

        uint256 releasable = releasableAmount();
        if (releasable > 0) {
            mockScheduleData.releasedAmount += releasable;
            emit TokensReleased(mockScheduleData.beneficiary, releasable);
            return releasable;
        } else {
            revert("MockVI: No tokens due");
        }
    }

    function revoke() external override returns (uint256 amount) {
        require(mockScheduleData.revocable, "MockVI: Not revocable");
        require(!mockScheduleData.revoked, "MockVI: Already revoked");
        mockScheduleData.revoked = true;
        uint256 vested = vestedAmount(block.timestamp);
        amount = mockScheduleData.totalAmount - vested;
        emit VestingRevoked(msg.sender, amount);
        return amount;
    }

    function getVestingSchedule() external view override returns (
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 duration,
        uint256 releasedAmount,
        bool revocable,
        bool revoked
    ) {
        return (
            mockScheduleData.beneficiary,
            mockScheduleData.totalAmount,
            mockScheduleData.startTime,
            mockScheduleData.cliffDuration,
            mockScheduleData.duration,
            mockScheduleData.releasedAmount,
            mockScheduleData.revocable,
            mockScheduleData.revoked
        );
    }

    function releasableAmount() public view override returns (uint256) {
        if (mockScheduleData.revoked) return 0;
        uint256 vested = vestedAmount(block.timestamp);
        if (vested > mockScheduleData.releasedAmount) {
            return vested - mockScheduleData.releasedAmount;
        }
        return 0;
    }

    function vestedAmount(uint256 timestamp) public view override returns (uint256 vested) {
        VestingScheduleData storage s = mockScheduleData; 

        if (timestamp < s.startTime + s.cliffDuration) return 0;
        if (timestamp >= s.startTime + s.duration) {
            vested = s.totalAmount;
        } else {
            uint256 timeElapsedSinceStart = timestamp - s.startTime;
            if (s.duration == 0) return s.totalAmount;
            vested = (s.totalAmount * timeElapsedSinceStart) / s.duration;
        }
        return vested > s.totalAmount ? s.totalAmount : vested;
    }


    function owner() external view override returns (address) {
        return mockScheduleData.scheduleOwner; 
    }
}