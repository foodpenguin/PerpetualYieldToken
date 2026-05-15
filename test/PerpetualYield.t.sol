// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "../src/PerpetualYield.sol";

contract MockFlashBorrower is IERC3156FlashBorrower {
    PerpetualYield public token;
    uint256 public feeToPay;
    bool public shouldRevert;
    bool public shouldNotApprove;

    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(PerpetualYield _token) {
        token = _token;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldNotApprove(bool _shouldNotApprove) external {
        shouldNotApprove = _shouldNotApprove;
    }

    function onFlashLoan(
        address initiator,
        address _token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(msg.sender == address(token), "Untrusted callback");
        require(initiator == address(this), "Untrusted initiator");
        
        if (shouldRevert) {
            revert("MockFlashBorrower: reverted");
        }

        feeToPay = fee;
        
        if (!shouldNotApprove) {
            token.approve(address(token), amount + fee);
        }
        
        return CALLBACK_SUCCESS;
    }

    function initiateFlashLoan(uint256 amount) external {
        token.flashLoan(this, address(token), amount, "");
    }
}

contract PerpetualYieldTest is Test {
    PerpetualYield public token;
    MockFlashBorrower public borrower;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        vm.warp(10000000); // Start at a normalized time
        token = new PerpetualYield();
        borrower = new MockFlashBorrower(token);
    }

    function testInitialState() public {
        assertEq(token.name(), "Perpetual Yield");
        assertEq(token.symbol(), "PY");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.owner(), owner);
    }

    function testExternalMint() public {
        token.externalMint(user1, 1000 * 1e18);
        assertEq(token.balanceOf(user1), 1000 * 1e18);
        assertEq(token.totalSupply(), 1000 * 1e18);
    }

    function testGracePeriod() public {
        token.externalMint(user1, 1000 * 1e18);
        assertEq(token.balanceOf(user1), 1000 * 1e18);

        // Advance 7 days exactly
        vm.warp(block.timestamp + 7 days);
        assertEq(token.balanceOf(user1), 1000 * 1e18);
    }

    function testExponentialDecay() public {
        token.externalMint(user1, 1000 * 1e18);

        // Advance 1 year
        vm.warp(block.timestamp + 365 days);
        uint256 balance1Year = token.balanceOf(user1);
        assertTrue(balance1Year < 1000 * 1e18, "Balance should have decayed");
        
        // Fast forward to 7 days + 5 years from mint
        vm.warp(block.timestamp + 4 * 365 days); // Total 5 years elapsed
        uint256 balance5Years = token.balanceOf(user1);
        
        // Should be around ~1% of 1000 * 1e18 (which is 10 * 1e18)
        assertApproxEqAbs(balance5Years, 10 * 1e18, 0.5 * 1e18); 
    }

    function testTransferUpdatesDecay() public {
        token.externalMint(user1, 1000 * 1e18);
        
        vm.warp(block.timestamp + 365 days);
        uint256 decayedBalance = token.balanceOf(user1);
        
        // Transfer 100 tokens to user2
        vm.prank(user1);
        token.transfer(user2, 100 * 1e18);

        assertEq(token.balanceOf(user1), decayedBalance - 100 * 1e18);
        assertEq(token.balanceOf(user2), 100 * 1e18);
        
        // Check timestamps updated
        assertEq(token.lastActivity(user1), block.timestamp);
        assertEq(token.lastActivity(user2), block.timestamp);
    }

    function testFlashLoan() public {
        uint256 amount = 1000 * 1e18;
        uint256 fee = token.flashFee(address(token), amount);
        
        // Mint fee to borrower so it can pay
        token.externalMint(address(borrower), fee);
        uint256 initialTotalSupply = token.totalSupply();

        borrower.initiateFlashLoan(amount);

        assertEq(borrower.feeToPay(), fee);
        assertEq(token.totalSupply(), initialTotalSupply - fee); // Fee should be burned
    }

    function testFlashLoanFailsNoApproval() public {
        uint256 amount = 1000 * 1e18;
        uint256 fee = token.flashFee(address(token), amount);
        token.externalMint(address(borrower), fee);

        borrower.setShouldNotApprove(true);
        vm.expectRevert(PerpetualYield.RepayNotApproved.selector);
        borrower.initiateFlashLoan(amount);
    }

    function testFlashLoanFailsInsufficientBalanceForFee() public {
        uint256 amount = 1000 * 1e18;
        // Do not mint fee to borrower
        vm.expectRevert(PerpetualYield.InsufficientBalance.selector);
        borrower.initiateFlashLoan(amount);
    }
}