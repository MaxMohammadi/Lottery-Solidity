pragma solidity ^0.6.6;

import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract BettingGame is VRFConsumerBase {
    uint256 internal fee;
    uint256 public randomResult;

    //Network: Rinkeby
    address constant VFRC_address = 0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B; // VRF Coordinator
    address constant LINK_address = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709; // LINK token

    //Seed for random generation
    uint256 constant half =
        57896044618658097711785492504343953926634992332820282019728792003956564819968;

    //Keyhash is the public key for which randomness is generated
    bytes32 internal constant keyHash =
        0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;

    uint256 public gameId;
    uint256 public lastGameId;
    address payable public admin;
    mapping(uint256 => Game) public games;

    struct Game {
        uint256 id;
        uint256 bet;
        uint256 seed;
        uint256 amount;
        address payable player;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "caller is not the admin");
        _;
    }

    modifier onlyVFRC() {
        require(msg.sender == VFRC_address, "only VFRC can call this function");
        _;
    }

    event Withdraw(address admin, uint256 amount);
    event Received(address indexed sender, uint256 amount);
    event Result(
        uint256 id,
        uint256 bet,
        uint256 randomSeed,
        uint256 amount,
        address player,
        uint256 winAmount,
        uint256 randomResult,
        uint256 time
    );

    constructor() public VRFConsumerBase(VFRC_address, LINK_address) {
        fee = 0.1 * 10**18; // 0.1 LINK
        admin = msg.sender;

        /** !UPDATE
         *
         * assign ETH/USD Rinkeby contract address to the aggregator variable.
         * more: https://docs.chain.link/docs/ethereum-addresses
         */

        ethUsd = AggregatorV3Interface(
            0x8A753747A1Fa494EC906cE90E9f37563A8AF630e
        );
    }

    /* Allows this contract to receive payments */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function game(uint256 bet, uint256 seed) public payable returns (bool) {
        //0 is low, refers to 1-3  dice values
        //1 is high, refers to 4-6 dice values
        require(bet <= 1, "bet must be 0 or 1");

        //vault balance must be at least equal to msg.value
        require(
            address(this).balance >= msg.value,
            "Error, insufficent vault balance"
        );

        //each bet has unique id
        games[gameId] = Game(gameId, bet, seed, msg.value, msg.sender); //msg.sender is the address who is betting

        //increase gameId for the next bet
        gameId = gameId + 1;

        //where we talk to chainlink
        getRandomNumber(seed);

        return true;
    }

    // code from chainlink docs
    function getRandomNumber(uint256 userProvidedSeed)
        internal
        returns (bytes32 requestId)
    {
        require(
            LINK.balanceOf(address(this)) > fee,
            "Error, not enough LINK - fill contract with faucet"
        );
        return requestRandomness(keyHash, fee);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;

        verdict(randomResult);
    }

    // send the payout to the winners
    function verdict(uint256 random) public payable onlyVFRC {
        //check bets from latest betting round, one by one
        for (uint256 i = lastGameId; i < gameId; i++) {
            //reset winAmount for current user
            uint256 winAmount = 0;

            //if user wins, then receives 2x of their betting amount
            if (
                (random >= half && games[i].bet == 1) ||
                (random < half && games[i].bet == 0)
            ) {
                winAmount = games[i].amount * 2;
                games[i].player.transfer(winAmount);
            }
            emit Result(
                games[i].id,
                games[i].bet,
                games[i].seed,
                games[i].amount,
                games[i].player,
                winAmount,
                random,
                block.timestamp
            );
        }
        //save current gameId to lastGameId for the next betting round
        lastGameId = gameId;
    }

    /**
     * Withdraw LINK from this contract (admin option).
     */
    function withdrawLink(uint256 amount) external onlyAdmin {
        require(LINK.transfer(msg.sender, amount), "Error, unable to transfer");
    }

    /**
     * Withdraw Ether from this contract (admin option).
     */
    function withdrawEther(uint256 amount) external payable onlyAdmin {
        require(
            address(this).balance >= amount,
            "Error, contract has insufficent balance"
        );
        admin.transfer(amount);

        emit Withdraw(admin, amount);
    }
}
