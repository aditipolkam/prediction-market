// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PredictionMarket {
    IERC20 public usdc;
    address public owner;
    uint256 public platformFee = 10; // 10%
    uint256 public donationFee = 5; // 5%
    uint256 public minimumParticipation = 100 * 10 ** 6; // 100 USDC with 6 decimals

    struct Bet {
        string description;
        uint256 yesPool;
        uint256 noPool;
        uint256 totalPool;
        uint256 endTime;
        bool isResolved;
        bool outcome; // true for yes, false for no
        address donationAddress;
        mapping(address => uint256) yesBets;
        mapping(address => uint256) noBets;
    }

    // Mapping of bet ID to Bet details
    mapping(uint256 => Bet) public bets;
    uint256 public betCounter;

    // Tracks user winnings for specific bets
    mapping(address => mapping(uint256 => uint256)) public userWinnings;

    event BetCreated(
        uint256 indexed betId,
        string description,
        address donationAddress,
        uint256 endTime
    );
    event BetPlaced(
        uint256 indexed betId,
        address indexed user,
        uint256 amount,
        bool betOnYes
    );
    event BetResolved(uint256 indexed betId, bool outcome);
    event WinningsClaimed(
        uint256 indexed betId,
        address indexed user,
        uint256 amount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor(IERC20 _usdc) {
        usdc = _usdc;
        owner = msg.sender;
    }

    // Create a new bet with donation address
    function createBet(
        string calldata description,
        address donationAddress,
        uint256 endTime
    ) external onlyOwner {
        require(endTime > block.timestamp, "End time must be in the future");

        betCounter++;
        Bet storage newBet = bets[betCounter];
        newBet.description = description;
        newBet.yesPool = 0;
        newBet.noPool = 0;
        newBet.totalPool = 0;
        newBet.endTime = endTime;
        newBet.isResolved = false;
        newBet.outcome = false;
        newBet.donationAddress = donationAddress;

        emit BetCreated(betCounter, description, donationAddress, endTime);
    }

    // Place a bet on Yes or No
    function placeBet(uint256 betId, uint256 amount, bool betOnYes) external {
        Bet storage bet = bets[betId];
        require(block.timestamp < bet.endTime, "Betting period has ended");
        require(amount > 0, "Amount must be greater than zero");

        usdc.transferFrom(msg.sender, address(this), amount);

        if (betOnYes) {
            bet.yesPool += amount;
            bet.yesBets[msg.sender] += amount;
        } else {
            bet.noPool += amount;
            bet.noBets[msg.sender] += amount;
        }

        bet.totalPool += amount;
        emit BetPlaced(betId, msg.sender, amount, betOnYes);
    }

    // Resolve the bet and set the outcome
    function resolveBet(uint256 betId, bool outcome) external onlyOwner {
        Bet storage bet = bets[betId];
        require(
            block.timestamp >= bet.endTime,
            "Betting period is still ongoing"
        );
        require(!bet.isResolved, "Bet already resolved");

        bet.isResolved = true;
        bet.outcome = outcome;

        // Check minimum participation for applying fees
        uint256 totalPool = bet.totalPool;
        uint256 platformCut = 0;
        uint256 donationCut = 0;

        if (
            bet.yesPool >= minimumParticipation &&
            bet.noPool >= minimumParticipation
        ) {
            platformCut = (totalPool * platformFee) / 100;
            donationCut = (totalPool * donationFee) / 100;

            usdc.transfer(owner, platformCut);
            usdc.transfer(bet.donationAddress, donationCut);
        }

        emit BetResolved(betId, outcome);
    }

    // Claim winnings for a specific bet
    function claimWinnings(uint256 betId) external {
        Bet storage bet = bets[betId];
        require(bet.isResolved, "Bet is not resolved yet");
        require(
            userWinnings[msg.sender][betId] == 0,
            "Winnings already claimed"
        );

        uint256 userBet;
        uint256 winningPool;
        uint256 totalWinnings;
        uint256 userShare;

        if (bet.outcome) {
            userBet = bet.yesBets[msg.sender];
            winningPool = bet.yesPool;
        } else {
            userBet = bet.noBets[msg.sender];
            winningPool = bet.noPool;
        }

        require(userBet > 0, "User did not participate or lost the bet");

        totalWinnings =
            (bet.totalPool * (100 - platformFee - donationFee)) /
            100;
        userShare = (userBet * totalWinnings) / winningPool;

        userWinnings[msg.sender][betId] = userShare;
        usdc.transfer(msg.sender, userShare);

        emit WinningsClaimed(betId, msg.sender, userShare);
    }

    // Get bet details
    function getBetDetails(
        uint256 betId
    )
        external
        view
        returns (
            string memory description,
            uint256 yesPool,
            uint256 noPool,
            uint256 totalPool,
            uint256 endTime,
            bool isResolved,
            bool outcome,
            address donationAddress
        )
    {
        Bet storage bet = bets[betId];
        return (
            bet.description,
            bet.yesPool,
            bet.noPool,
            bet.totalPool,
            bet.endTime,
            bet.isResolved,
            bet.outcome,
            bet.donationAddress
        );
    }
}
