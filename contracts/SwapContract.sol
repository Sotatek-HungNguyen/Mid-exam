// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract SwapContract is Initializable, ReentrancyGuardUpgradeable {
    // Address of the contract owner
    address public owner;

    // Address of the treasury wallet for fees
    address public treasury;

    // Fee percentage for transactions (in basis points)
    uint256 public feePercentage;

    // Mapping to store Swap Request information
    mapping(uint256 => SwapRequest) public swapRequests;

    // Struct to define Swap Request details
    struct SwapRequest {
        uint256 id;
        address sender;
        address receiver;
        address tokenIn; // Address of the token being sent by the sender
        address tokenOut; // Address of the token desired by the receiver
        uint256 amountIn;
        bool approved;
        bool cancelled;
    }

    // Modifier to restrict functions to the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Constructor (called during upgrade)
    function initialize(address _owner, address _treasury, uint256 _feePercentage) public initializer {
        __ReentrancyGuard_init();
        owner = _owner;
        treasury = _treasury;
        feePercentage = _feePercentage;
    }

    // Function to create a Swap Request
    function createSwapRequest(address _receiver, address _tokenIn, address _tokenOut, uint256 _amountIn) public {
        require(_amountIn > 0, "Swap amount must be greater than 0");
        require(isSupportedToken(_tokenIn) && isSupportedToken(_tokenOut), "Unsupported token(s)");

        // Get ERC20 token instances
        IERC20Upgradeable tokenIn = IERC20Upgradeable(_tokenIn);
        IERC20Upgradeable tokenOut = IERC20Upgradeable(_tokenOut);

        // Transfer tokens from sender to the contract (using safe transfer)
        bool transferSuccess = tokenIn.transferFrom(msg.sender, address(this), _amountIn);
        require(transferSuccess, "Transfer of tokens failed");

        // Create a new Swap Request
        uint256 id = swapRequests.length + 1;
        swapRequests[id] = SwapRequest({
        id : id,
        sender : msg.sender,
        receiver : _receiver,
        tokenIn : _tokenIn,
        tokenOut : _tokenOut,
        amountIn : _amountIn,
        approved : false,
        cancelled : false
        });
        emit SwapRequestCreated(id, msg.sender, _receiver, _amountIn, _tokenIn, _tokenOut);
    }

    // Function for the receiver to approve a Swap Request (non-reentrant)
    function approveSwapRequest(uint256 _id) public {
        SwapRequest storage swapRequest = swapRequests[_id];

        // Validate request details
        require(swapRequest.sender != msg.sender, "Cannot approve own request");
        require(!swapRequest.approved, "Swap Request already approved");
        require(!swapRequest.cancelled, "Swap Request already cancelled");

        // Get ERC20 token instances
        IERC20Upgradeable tokenIn = IERC20Upgradeable(swapRequest.tokenIn);
        IERC20Upgradeable tokenOut = IERC20Upgradeable(swapRequest.tokenOut);

        uint256 amountOut = swapRequest.amountIn * 3;
        // Check if the contract has enough tokens to fulfill the swap
        require(tokenOut.balanceOf(address(this)) >= amountOut, "Insufficient token balance for swap");

        // Transfer tokens from receiver to the contract (using safe transfer) for potential fee payment
        bool transferSuccess = tokenIn.transferFrom(msg.sender, address(this), swapRequest.amountIn * feePercentage / 10000);
        require(transferSuccess, "Transfer of tokens for fee failed");

        // Calculate transfer amount after fee deduction
        uint256 transferAmount = swapRequest.amountIn - (swapRequest.amountIn * feePercentage / 10000);

        // Transfer tokenIn to treasury for fee
        tokenIn.transfer(treasury, transferAmount * feePercentage / 10000);

        // Transfer tokenOut to receiver
        tokenOut.transfer(swapRequest.receiver, amountOut);

        // Update Swap Request status and emit event
        swapRequest.approved = true;
        emit SwapRequestStatusChanged(_id, true, false);
    }

    // Function for the sender to reject a Swap Request (non-reentrant)
    function rejectSwapRequest(uint256 _id) public {
        SwapRequest storage swapRequest = swapRequests[_id];

        // Validate request details
        require(swapRequest.receiver != msg.sender, "Cannot reject someone else's request");
        require(!swapRequest.approved, "Swap Request already approved");
        require(!swapRequest.cancelled, "Swap Request already cancelled");

        // Get ERC20 token instance for the token being sent by the sender
        IERC20Upgradeable token = IERC20Upgradeable(swapRequest.tokenIn);

        // Transfer the original token amount back to the sender (using safe transfer)
        bool transferSuccess = token.transfer(swapRequest.sender, swapRequest.amountIn);
        require(transferSuccess, "Transfer of tokens failed");

        // Update Swap Request status and emit event
        swapRequest.cancelled = true;
        emit SwapRequestStatusChanged(_id, false, true);
    }
}

