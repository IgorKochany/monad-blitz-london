// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title RideMarket — peer-to-peer ride auctions with escrow. Zero fees, no middleman.
/// Flow: rider posts a trip (optionally pre-escrowing a max price for auto-accept),
/// drivers bid under the rider's time limit, rider accepts (or a low-enough bid
/// auto-matches instantly), funds sit in escrow, rider confirms completion -> driver paid.
contract RideMarket {
    enum Status { Open, Matched, Completed, Cancelled }

    struct Ride {
        address rider;
        string  fromLoc;
        string  toLoc;
        uint256 maxPrice;    // 0 = no auto-accept threshold
        uint256 expiry;      // unix time: no new bids/acceptance after this
        Status  status;
        address driver;      // set on match
        uint256 agreedPrice; // amount owed to driver on completion
        uint256 deposit;     // MON currently escrowed for this ride
    }

    struct Bid {
        address driver;
        uint256 price;
        uint256 expiry;      // unix time this bid stops being acceptable
        bool    active;
    }

    uint256 public rideCount;
    mapping(uint256 => Ride) public rides;
    mapping(uint256 => Bid[]) public bids;

    event RidePosted(uint256 indexed rideId, address indexed rider, string fromLoc, string toLoc, uint256 maxPrice, uint256 expiry, uint256 deposit);
    event BidPlaced(uint256 indexed rideId, uint256 indexed bidId, address indexed driver, uint256 price, uint256 expiry);
    event Matched(uint256 indexed rideId, address indexed driver, uint256 price, bool autoAccepted);
    event Completed(uint256 indexed rideId, address indexed driver, uint256 price);
    event Cancelled(uint256 indexed rideId);

    /// Post a trip. Send MON as msg.value to enable instant auto-accept:
    /// the deposit is your max price, and the first bid at or under it wins immediately
    /// (you're refunded the difference). Send 0 to review bids manually.
    function postRide(
        string calldata fromLoc,
        string calldata toLoc,
        uint256 maxPrice,
        uint256 expiry
    ) external payable returns (uint256 rideId) {
        require(expiry > block.timestamp, "expiry in past");
        if (msg.value > 0) {
            require(maxPrice == msg.value, "deposit must equal maxPrice");
        }
        rideId = rideCount++;
        rides[rideId] = Ride({
            rider: msg.sender,
            fromLoc: fromLoc,
            toLoc: toLoc,
            maxPrice: maxPrice,
            expiry: expiry,
            status: Status.Open,
            driver: address(0),
            agreedPrice: 0,
            deposit: msg.value
        });
        emit RidePosted(rideId, msg.sender, fromLoc, toLoc, maxPrice, expiry, msg.value);
    }

    /// Bid on an open ride. If the rider pre-escrowed and your price is at or
    /// under their max, you're matched instantly.
    function bid(uint256 rideId, uint256 price, uint256 bidExpiry) external {
        Ride storage r = rides[rideId];
        require(r.status == Status.Open, "ride not open");
        require(block.timestamp < r.expiry, "ride expired");
        require(msg.sender != r.rider, "rider cannot bid");
        require(price > 0, "price required");
        require(bidExpiry > block.timestamp, "bid expiry in past");

        bids[rideId].push(Bid(msg.sender, price, bidExpiry, true));
        emit BidPlaced(rideId, bids[rideId].length - 1, msg.sender, price, bidExpiry);

        // Auto-accept: rider escrowed a max price and this bid beats it.
        if (r.deposit > 0 && price <= r.deposit) {
            uint256 refund = r.deposit - price;
            r.status = Status.Matched;
            r.driver = msg.sender;
            r.agreedPrice = price;
            r.deposit = price;
            emit Matched(rideId, msg.sender, price, true);
            if (refund > 0) {
                (bool ok, ) = r.rider.call{value: refund}("");
                require(ok, "refund failed");
            }
        }
    }

    /// Rider manually accepts a bid. msg.value + existing deposit must cover the price;
    /// any excess deposit is refunded.
    function acceptBid(uint256 rideId, uint256 bidId) external payable {
        Ride storage r = rides[rideId];
        require(msg.sender == r.rider, "not your ride");
        require(r.status == Status.Open, "ride not open");
        Bid storage b = bids[rideId][bidId];
        require(b.active, "bid inactive");
        require(block.timestamp < b.expiry, "bid expired");

        uint256 total = r.deposit + msg.value;
        require(total >= b.price, "insufficient escrow");
        uint256 refund = total - b.price;

        r.status = Status.Matched;
        r.driver = b.driver;
        r.agreedPrice = b.price;
        r.deposit = b.price;
        emit Matched(rideId, b.driver, b.price, false);

        if (refund > 0) {
            (bool ok, ) = r.rider.call{value: refund}("");
            require(ok, "refund failed");
        }
    }

    /// Rider confirms the ride happened -> escrow released to driver.
    function completeRide(uint256 rideId) external {
        Ride storage r = rides[rideId];
        require(msg.sender == r.rider, "not your ride");
        require(r.status == Status.Matched, "not matched");
        r.status = Status.Completed;
        uint256 amount = r.deposit;
        r.deposit = 0;
        emit Completed(rideId, r.driver, amount);
        (bool ok, ) = r.driver.call{value: amount}("");
        require(ok, "payout failed");
    }

    /// Rider cancels an open (unmatched) ride and reclaims any deposit.
    function cancelRide(uint256 rideId) external {
        Ride storage r = rides[rideId];
        require(msg.sender == r.rider, "not your ride");
        require(r.status == Status.Open, "ride not open");
        r.status = Status.Cancelled;
        uint256 refund = r.deposit;
        r.deposit = 0;
        emit Cancelled(rideId);
        if (refund > 0) {
            (bool ok, ) = r.rider.call{value: refund}("");
            require(ok, "refund failed");
        }
    }

    /// Driver withdraws a bid they no longer want honored.
    function withdrawBid(uint256 rideId, uint256 bidId) external {
        Bid storage b = bids[rideId][bidId];
        require(msg.sender == b.driver, "not your bid");
        require(rides[rideId].status == Status.Open, "ride not open");
        b.active = false;
    }

    // ---- Read helpers for the frontend ----

    function bidCount(uint256 rideId) external view returns (uint256) {
        return bids[rideId].length;
    }
}
