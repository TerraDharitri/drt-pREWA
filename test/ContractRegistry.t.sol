// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../contracts/core/ContractRegistry.sol";
import "../contracts/access/AccessControl.sol";
import "../contracts/mocks/MockAccessControl.sol"; 
import "../contracts/libraries/Errors.sol";
import "../contracts/proxy/TransparentProxy.sol";

contract ContractRegistryTest is Test {
    ContractRegistry registry;
    MockAccessControl mockAC;

    address owner;
    address parameterAdmin;
    address user1;
    address proxyAdmin;

    address contractAddr1;
    address contractAddr2;
    address contractAddr3;

    function setUp() public {
        owner = makeAddr("owner");
        parameterAdmin = makeAddr("parameterAdmin");
        user1 = makeAddr("user1");
        proxyAdmin = makeAddr("proxyAdmin"); 

        contractAddr1 = makeAddr("contractAddr1");
        vm.etch(contractAddr1, bytes("some bytecode")); 
        contractAddr2 = makeAddr("contractAddr2");
        vm.etch(contractAddr2, bytes("some bytecode"));
        contractAddr3 = makeAddr("contractAddr3");
        vm.etch(contractAddr3, bytes("some bytecode"));


        mockAC = new MockAccessControl();
        vm.prank(owner); 
        mockAC.setRole(mockAC.DEFAULT_ADMIN_ROLE(), owner, true); 
        mockAC.setRoleAdmin(mockAC.PARAMETER_ROLE(), mockAC.DEFAULT_ADMIN_ROLE());
        mockAC.setRole(mockAC.PARAMETER_ROLE(), parameterAdmin, true);

        ContractRegistry logic = new ContractRegistry();
        // Use two-step initialization to avoid test environment issues
        TransparentProxy proxy = new TransparentProxy(address(logic), proxyAdmin, "");
        registry = ContractRegistry(address(proxy));
        registry.initialize(owner, address(mockAC));
    }

    function test_Initialize_Success() public view { 
        assertEq(registry.owner(), owner);
        assertEq(address(registry.accessControl()), address(mockAC));
    }

    function test_Initialize_Revert_ZeroOwner() public {
        ContractRegistry logic = new ContractRegistry();
        bytes memory data = abi.encodeWithSelector(logic.initialize.selector, address(0), address(mockAC));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "initialOwner"));
        new TransparentProxy(address(logic), proxyAdmin, data);
    }

    function test_Initialize_Revert_ZeroAccessControl() public {
        ContractRegistry logic = new ContractRegistry();
        bytes memory data = abi.encodeWithSelector(logic.initialize.selector, owner, address(0));
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector, "accessControlAddress for ContractRegistry"));
        new TransparentProxy(address(logic), proxyAdmin, data);
    }

    function test_Initialize_Revert_AlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        registry.initialize(owner, address(mockAC));
    }
    
    function test_Constructor_Runs() public {
        new ContractRegistry(); 
        assertTrue(true, "Constructor ran");
    }

    function test_Modifier_OnlyParameterRole_Fail_NoRole() public {
        vm.prank(user1); 
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, mockAC.PARAMETER_ROLE()));
        registry.registerContract("Test", contractAddr1, "TypeA", "v1");
    }
    function test_Modifier_OnlyParameterRole_Fail_ACZero() public {
        ContractRegistry rawRegistry = new ContractRegistry(); 
        vm.prank(parameterAdmin); 
        vm.expectRevert(CR_AccessControlZero.selector);
        rawRegistry.registerContract("Test", contractAddr1, "TypeA", "v1");
    }
     function test_Modifier_OnlyParameterRole_Success() public {
        vm.prank(parameterAdmin);
        registry.registerContract("TestSuccess", contractAddr1, "TypeA", "v1");
        assertTrue(true, "Call with parameter role succeeded");
    }

    function test_RegisterContract_Success() public {
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        emit ContractRegistry.ContractRegistered("Contract1", contractAddr1, "TypeA", "1.0", parameterAdmin);
        assertTrue(registry.registerContract("Contract1", contractAddr1, "TypeA", "1.0"));

        (address addr, string memory cType, string memory ver, bool active, uint256 regTime, address registrar) = 
            registry.getContractInfo("Contract1");
        assertEq(addr, contractAddr1);
        assertEq(cType, "TypeA");
        assertEq(ver, "1.0");
        assertTrue(active);
        assertTrue(regTime <= block.timestamp && regTime > 0);
        assertEq(registrar, parameterAdmin);
        assertEq(registry.getContractName(contractAddr1), "Contract1");
        assertEq(registry.getContractCount(), 1);
        (string[] memory namesPage, address[] memory addrs, uint256 totalTypeA) = registry.getContractsByType("TypeA", 0, 1); 
        assertEq(totalTypeA, 1);
        assertEq(namesPage.length, 1); 
        assertEq(addrs.length, 1);
        assertEq(namesPage[0], "Contract1");
        assertEq(addrs[0], contractAddr1);
    }

    function test_RegisterContract_Revert_EmptyName() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_NameEmpty.selector);
        registry.registerContract("", contractAddr1, "TypeA", "1.0");
    }
    function test_RegisterContract_Revert_ContractAddressZero() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_ContractAddressZero.selector, "contractAddress_"));
        registry.registerContract("Contract1", address(0), "TypeA", "1.0");
    }
    function test_RegisterContract_Revert_EmptyType() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_ContractTypeEmpty.selector);
        registry.registerContract("Contract1", contractAddr1, "", "1.0");
    }
    function test_RegisterContract_Revert_EmptyVersion() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_VersionEmpty.selector);
        registry.registerContract("Contract1", contractAddr1, "TypeA", "");
    }
    function test_RegisterContract_Revert_NameAlreadyRegistered() public {
        vm.prank(parameterAdmin);
        registry.registerContract("Contract1", contractAddr1, "TypeA", "1.0");
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_NameAlreadyRegistered.selector, "Contract1"));
        registry.registerContract("Contract1", contractAddr2, "TypeB", "2.0");
    }
    function test_RegisterContract_Revert_AddressAlreadyRegistered() public {
        vm.prank(parameterAdmin);
        registry.registerContract("Contract1", contractAddr1, "TypeA", "1.0");
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_AddressAlreadyRegistered.selector, contractAddr1));
        registry.registerContract("Contract2", contractAddr1, "TypeB", "2.0");
    }

    function test_UpdateContract_Success_AddressAndVersionChange() public {
        vm.prank(parameterAdmin);
        registry.registerContract("Contract1", contractAddr1, "TypeA", "1.0");
        
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, false); 
        emit ContractRegistry.ContractUpdated("Contract1", contractAddr1, contractAddr2, "2.0", parameterAdmin);
        assertTrue(registry.updateContract("Contract1", contractAddr2, "2.0"));

        (address addr,, string memory ver,,,) = registry.getContractInfo("Contract1");
        assertEq(addr, contractAddr2);
        assertEq(ver, "2.0");
        assertEq(registry.getContractName(contractAddr1), ""); 
        assertEq(registry.getContractName(contractAddr2), "Contract1");
    }

    function test_UpdateContract_Success_VersionOnlyChange() public {
        vm.prank(parameterAdmin);
        registry.registerContract("Contract1", contractAddr1, "TypeA", "1.0");

        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, false);
        emit ContractRegistry.ContractUpdated("Contract1", contractAddr1, contractAddr1, "1.1", parameterAdmin);
        assertTrue(registry.updateContract("Contract1", contractAddr1, "1.1"));
        
        (,, string memory ver,,,) = registry.getContractInfo("Contract1");
        assertEq(ver, "1.1");
        assertEq(registry.getContractName(contractAddr1), "Contract1"); 
    }

    function test_UpdateContract_Reverts() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_NameEmpty.selector);
        registry.updateContract("", contractAddr2, "2.0");

        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1");

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_ContractAddressZero.selector, "newContractAddress"));
        registry.updateContract("C1", address(0), "2.0");
        
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_VersionEmpty.selector);
        registry.updateContract("C1", contractAddr2, "");

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_ContractNotFound.selector, "C_NotFound"));
        registry.updateContract("C_NotFound", contractAddr2, "2.0");

        vm.prank(parameterAdmin);
        registry.registerContract("C2", contractAddr2, "T", "1"); 

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_AddressAlreadyRegistered.selector, contractAddr2));
        registry.updateContract("C1", contractAddr2, "2.0");
    }

    function test_RemoveContract_Success_ItemNotLast() public {
        vm.startPrank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "TypeA", "1");
        registry.registerContract("C2", contractAddr2, "TypeA", "1");
        registry.registerContract("C3", contractAddr3, "TypeA", "1");
        assertEq(registry.getContractCount(), 3);

        vm.expectEmit(true, true, false, true);
        emit ContractRegistry.ContractRemoved("C2", contractAddr2, parameterAdmin);
        assertTrue(registry.removeContract("C2"));
        vm.stopPrank();

        assertEq(registry.getContractCount(), 2);
        assertEq(registry.getContractAddress("C2"), address(0)); 
        assertEq(registry.getContractName(contractAddr2), "");
        
        (string[] memory allNamesPage, ) = registry.listContracts(0, 3); 
        assertEq(allNamesPage.length, 2);
        assertEq(allNamesPage[0], "C1");
        assertEq(allNamesPage[1], "C3");


        (string[] memory typeANamesPage, , ) = registry.getContractsByType("TypeA", 0, 3); 
        assertEq(typeANamesPage.length, 2);
        assertEq(typeANamesPage[0], "C1");
        assertEq(typeANamesPage[1], "C3");
    }

    function test_RemoveContract_Success_ItemIsLast() public {
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "TypeA", "1");
        vm.prank(parameterAdmin);
        assertTrue(registry.removeContract("C1"));
        assertEq(registry.getContractCount(), 0);
    }

    function test_RemoveContract_Success_LastForItsType_TypeBecomesEmpty() public {
        vm.startPrank(parameterAdmin);
        registry.registerContract("C_TypeA", contractAddr1, "TypeA", "1");
        registry.registerContract("C_TypeB", contractAddr2, "TypeB", "1");
        
        assertTrue(registry.removeContract("C_TypeA"));
        vm.stopPrank();

        (string[] memory typeANamesPage,,uint256 totalTypeA) = registry.getContractsByType("TypeA", 0, 1);
        assertEq(totalTypeA, 0);
        assertEq(typeANamesPage.length, 0);
    }
    
    function test_RemoveContract_Reverts() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_NameEmpty.selector);
        registry.removeContract("");
        
        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_ContractNotFound.selector, "C_NotFound"));
        registry.removeContract("C_NotFound");
    }

    function test_SetContractActive_Success() public {
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1"); 
        
        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        emit ContractRegistry.ContractActivationChanged("C1", contractAddr1, false, parameterAdmin);
        assertTrue(registry.setContractActive("C1", false));
        (,,,bool active,,) = registry.getContractInfo("C1"); 
        assertFalse(active);

        vm.prank(parameterAdmin);
        vm.expectEmit(true, true, true, true);
        emit ContractRegistry.ContractActivationChanged("C1", contractAddr1, true, parameterAdmin);
        assertTrue(registry.setContractActive("C1", true));
        (,,,bool newActive,,) = registry.getContractInfo("C1"); 
        assertTrue(newActive);
    }

    function test_SetContractActive_NoChange() public {
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1");
        vm.prank(parameterAdmin);
        assertTrue(registry.setContractActive("C1", true)); 
    }
    
    function test_SetContractActive_Reverts() public {
        vm.prank(parameterAdmin);
        vm.expectRevert(CR_NameEmpty.selector);
        registry.setContractActive("", false);

        vm.prank(parameterAdmin);
        vm.expectRevert(abi.encodeWithSelector(CR_ContractNotFound.selector, "C_NotFound"));
        registry.setContractActive("C_NotFound", false);
    }

    function test_GetContractAddress_SuccessAndNotFound() public {
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1");
        assertEq(registry.getContractAddress("C1"), contractAddr1);
        assertEq(registry.getContractAddress("C_NotFound"), address(0));
    }

    function test_GetContractName_SuccessAndNotFound() public {
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1");
        assertEq(registry.getContractName(contractAddr1), "C1");
        assertEq(registry.getContractName(contractAddr2), ""); 
    }

    function test_GetContractInfo_Revert_NotFound() public {
        vm.expectRevert(abi.encodeWithSelector(CR_ContractNotFound.selector, "C_NotFound"));
        registry.getContractInfo("C_NotFound");
    }

    function test_ListContracts_Pagination() public {
        vm.startPrank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T1", "1");
        registry.registerContract("C2", contractAddr2, "T2", "1");
        registry.registerContract("C3", contractAddr3, "T3", "1");
        vm.stopPrank();

        (string[] memory page, uint256 total) = registry.listContracts(0, 2);
        assertEq(total, 3); assertEq(page.length, 2); assertEq(page[0], "C1"); assertEq(page[1], "C2");

        (page, total) = registry.listContracts(1, 1);
        assertEq(total, 3); assertEq(page.length, 1); assertEq(page[0], "C2");

        (page, total) = registry.listContracts(2, 5); 
        assertEq(total, 3); assertEq(page.length, 1); assertEq(page[0], "C3");
        
        (page, total) = registry.listContracts(3, 1); 
        assertEq(total, 3); assertEq(page.length, 0);

        vm.expectRevert(CR_LimitIsZero.selector);
        registry.listContracts(0, 0);
        
        ContractRegistry emptyRegLogic = new ContractRegistry();
        TransparentProxy emptyProxy = new TransparentProxy(address(emptyRegLogic), proxyAdmin, "");
        ContractRegistry emptyReg = ContractRegistry(address(emptyProxy));
        emptyReg.initialize(owner, address(mockAC));

        (page, total) = emptyReg.listContracts(0, 1);
        assertEq(total, 0); assertEq(page.length, 0);
    }

    function test_GetContractsByType_Pagination() public {
        vm.startPrank(parameterAdmin);
        registry.registerContract("CA1", contractAddr1, "TypeA", "1");
        registry.registerContract("CB1", contractAddr2, "TypeB", "1");
        registry.registerContract("CA2", contractAddr3, "TypeA", "1");
        vm.stopPrank();

        (string[] memory names, address[] memory addrs, uint256 total) = 
            registry.getContractsByType("TypeA", 0, 1);
        assertEq(total, 2); assertEq(names.length, 1); assertEq(addrs.length, 1);
        assertEq(names[0], "CA1"); assertEq(addrs[0], contractAddr1);

        (names, addrs, total) = registry.getContractsByType("TypeA", 1, 5);
        assertEq(total, 2); assertEq(names.length, 1); assertEq(addrs.length, 1);
        assertEq(names[0], "CA2"); assertEq(addrs[0], contractAddr3);
        
        (names, addrs, total) = registry.getContractsByType("TypeC", 0, 1); 
        assertEq(total, 0); assertEq(names.length, 0);

        vm.expectRevert(CR_LimitIsZero.selector);
        registry.getContractsByType("TypeA", 0, 0);
        
        (names, addrs, total) = registry.getContractsByType("TypeA", 2, 1); 
        assertEq(total, 2); assertEq(names.length, 0);
    }

    function test_ContractExists_States() public {
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1"); 
        (bool exists, bool isActive) = registry.contractExists("C1");
        assertTrue(exists); assertTrue(isActive);

        vm.prank(parameterAdmin);
        registry.setContractActive("C1", false); 
        (exists, isActive) = registry.contractExists("C1");
        assertTrue(exists); assertFalse(isActive);
        
        (exists, isActive) = registry.contractExists("C_NotFound"); 
        assertFalse(exists); assertFalse(isActive);
    }

    function test_GetContractCount_EmptyAndPopulated() public {
        assertEq(registry.getContractCount(), 0);
        vm.prank(parameterAdmin);
        registry.registerContract("C1", contractAddr1, "T", "1");
        assertEq(registry.getContractCount(), 1);
    }
}