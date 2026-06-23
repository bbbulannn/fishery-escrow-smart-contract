// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CircularEscrowFishery
 * @dev Smart contract escrow with SLA-gated 
 *      settlement and circular routing logic
 *      for fishery supply chain governance
 * @notice Implements Algorithm 1 (Traceability),
 *         Algorithm 2 (Quality-Assured Procurement),
 *         Algorithm 3 (Circular Routing Logic)
 */
contract CircularEscrowFishery {

    // ─────────────────────────────────────
    // ENUMS & STRUCTS
    // ─────────────────────────────────────

    enum OrderStatus {
        Created,
        Funded,
        Shipped,
        Received,
        QualityAssessed,
        Settled,
        Disputed,
        CircularRouted
    }

    enum QIOutcome {
        PASS,       // QI >= 85
        PARTIAL,    // 70 <= QI < 85
        FAIL        // QI < 70
    }

    enum ValorizationRoute {
        FISHMEAL_PROCESSOR,
        BIOGAS_FACILITY,
        DEFAULT
    }

    struct Order {
        bytes32 orderID;
        bytes32 lotID;
        address buyer;
        address seller;
        uint256 quantity;       // in kg
        uint256 unitPrice;      // in wei per kg
        uint256 escrowValue;    // total locked
        uint256 qiScore;        // 0-100
        QIOutcome outcome;
        OrderStatus status;
        uint256 createdAt;
        ValorizationRoute route;
        bytes32 subOrderID;
    }

    struct SLAParams {
        uint256 maxTempC;       // max temperature °C
        uint256 maxMinutes;     // max minutes above
        uint256 alpha;          // weight for duration
        uint256 beta;           // weight for magnitude
        uint256 salvageRatioFishmeal;  // e.g., 35 = 35%
        uint256 salvageRatioBiogas;    // e.g., 15 = 15%
    }

    struct LotRecord {
        bytes32 lotID;
        address currentHolder;
        string  batchType;      // "PROTEIN_GRADE" | 
                                // "LOW_GRADE"
        uint256 timestamp;
        string  status;
        bytes32 routingProof;
    }

    struct ValorizationPartner {
        address partnerAddress;
        ValorizationRoute route;
        bool    isActive;
        string  name;
    }

    // ─────────────────────────────────────
    // STATE VARIABLES
    // ─────────────────────────────────────

    address public owner;
    address public oracle;

    mapping(bytes32 => Order)      public orders;
    mapping(bytes32 => SLAParams)  public slaParams;
    mapping(bytes32 => LotRecord)  public lotRegistry;
    mapping(address => bool)       public authorizedStakeholders;
    
    // Pre-registered valorization partners
    ValorizationPartner[] public valorizationPartners;

    uint256 public constant PASS_THRESHOLD    = 85;
    uint256 public constant PARTIAL_THRESHOLD = 70;

    // ─────────────────────────────────────
    // EVENTS — Algorithm 1 (Traceability)
    // ─────────────────────────────────────

    event ActivityRecorded(
        bytes32 indexed lotID,
        address indexed stakeholder,
        string  activity,
        string  location,
        bytes32 dataHash,
        uint256 timestamp
    );

    event LocationUpdated(
        bytes32 indexed lotID,
        string  newLocation,
        uint256 timestamp
    );

    event OriginVerified(
        bytes32 indexed lotID,
        address originStakeholder,
        uint256 originTimestamp
    );

    // ─────────────────────────────────────
    // EVENTS — Algorithm 2 (Procurement)
    // ─────────────────────────────────────

    event OrderCreated(
        bytes32 indexed orderID,
        bytes32 indexed lotID,
        address buyer,
        address seller,
        uint256 escrowValue
    );

    event EscrowFunded(
        bytes32 indexed orderID,
        uint256 amount,
        uint256 timestamp
    );

    event QualityAssessed(
        bytes32 indexed orderID,
        uint256 qiScore,
        QIOutcome outcome
    );

    event EscrowReleased(
        bytes32 indexed orderID,
        address indexed seller,
        uint256 amount,
        string  outcome
    );

    event PartialSettlement(
        bytes32 indexed orderID,
        address indexed seller,
        uint256 proportionalPayment,
        uint256 penalty
    );

    // ─────────────────────────────────────
    // EVENTS — Algorithm 3 (Circular Routing)
    // ─────────────────────────────────────

    event PrimaryPaymentWithheld(
        bytes32 indexed orderID,
        uint256 penaltyAmount
    );

    event SalvagePaymentReleased(
        bytes32 indexed orderID,
        address indexed seller,
        uint256 salvageValue,
        ValorizationRoute route
    );

    event CircularRoutingTriggered(
        bytes32 indexed orderID,
        bytes32 indexed subOrderID,
        address indexed valorizationPartner,
        ValorizationRoute route,
        uint256 salvageValue
    );

    event CircularRouteCompleted(
        bytes32 indexed lotID,
        bytes32 indexed orderID,
        ValorizationRoute route,
        uint256 timestamp
    );

    // ─────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, 
            "Not authorized: owner only");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, 
            "Not authorized: oracle only");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedStakeholders[msg.sender],
            "Not authorized stakeholder"
        );
        _;
    }

    modifier onlyBuyer(bytes32 orderID) {
        require(
            msg.sender == orders[orderID].buyer,
            "Not authorized: buyer only"
        );
        _;
    }

    modifier onlySeller(bytes32 orderID) {
        require(
            msg.sender == orders[orderID].seller,
            "Not authorized: seller only"
        );
        _;
    }

    // ─────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────

    constructor(address _oracle) {
        owner  = msg.sender;
        oracle = _oracle;
        authorizedStakeholders[msg.sender] = true;
    }

    // ─────────────────────────────────────
    // ADMIN FUNCTIONS
    // ─────────────────────────────────────

    function authorizeStakeholder(
        address stakeholder
    ) external onlyOwner {
        authorizedStakeholders[stakeholder] = true;
    }

    function registerValorizationPartner(
        address partnerAddress,
        ValorizationRoute route,
        string memory name
    ) external onlyOwner {
        valorizationPartners.push(ValorizationPartner({
            partnerAddress: partnerAddress,
            route:          route,
            isActive:       true,
            name:           name
        }));
    }

    // ─────────────────────────────────────
    // ALGORITHM 1: TRACEABILITY FUNCTIONS
    // ─────────────────────────────────────

    /**
     * @dev Records a supply chain activity 
     *      on-chain as immutable event log
     */
    function recordActivity(
        bytes32 lotID,
        string  memory activity,
        string  memory location,
        bytes32 dataHash
    ) external onlyAuthorized {
        
        // Update lot registry
        lotRegistry[lotID].lotID          = lotID;
        lotRegistry[lotID].currentHolder  = msg.sender;
        lotRegistry[lotID].timestamp      = block.timestamp;
        lotRegistry[lotID].status         = activity;

        emit ActivityRecorded(
            lotID,
            msg.sender,
            activity,
            location,
            dataHash,
            block.timestamp
        );
    }

    /**
     * @dev Updates GPS location of a lot
     */
    function updateLocation(
        bytes32 lotID,
        string  memory newLocation
    ) external onlyAuthorized {
        require(
            lotRegistry[lotID].lotID == lotID,
            "Lot not registered"
        );

        emit LocationUpdated(
            lotID,
            newLocation,
            block.timestamp
        );
    }

    /**
     * @dev Returns origin data for a lot
     */
    function verifyProductOrigin(
        bytes32 lotID
    ) external returns (
        address originHolder,
        uint256 originTimestamp
    ) {
        LotRecord memory record = lotRegistry[lotID];
        
        emit OriginVerified(
            lotID,
            record.currentHolder,
            record.timestamp
        );

        return (
            record.currentHolder,
            record.timestamp
        );
    }

    // ─────────────────────────────────────
    // ALGORITHM 2: PROCUREMENT FUNCTIONS
    // ─────────────────────────────────────

    /**
     * @dev Creates a new procurement order
     *      and initializes escrow structure
     */
    function createOrder(
        bytes32 orderID,
        bytes32 lotID,
        address seller,
        uint256 quantity,
        uint256 unitPrice
    ) external {
        require(
            orders[orderID].createdAt == 0,
            "Order already exists"
        );

        orders[orderID] = Order({
            orderID:     orderID,
            lotID:       lotID,
            buyer:       msg.sender,
            seller:      seller,
            quantity:    quantity,
            unitPrice:   unitPrice,
            escrowValue: 0,
            qiScore:     0,
            outcome:     QIOutcome.PASS,
            status:      OrderStatus.Created,
            createdAt:   block.timestamp,
            route:       ValorizationRoute.DEFAULT,
            subOrderID:  bytes32(0)
        });

        emit OrderCreated(
            orderID,
            lotID,
            msg.sender,
            seller,
            quantity * unitPrice
        );
    }

    /**
     * @dev Sets SLA parameters for an order
     */
    function setSLAParams(
        bytes32 orderID,
        uint256 maxTempC,
        uint256 maxMinutes,
        uint256 alpha,
        uint256 beta,
        uint256 salvageRatioFishmeal,
        uint256 salvageRatioBiogas
    ) external onlyBuyer(orderID) {
        require(
            orders[orderID].status 
                == OrderStatus.Created,
            "Order not in Created state"
        );

        slaParams[orderID] = SLAParams({
            maxTempC:              maxTempC,
            maxMinutes:            maxMinutes,
            alpha:                 alpha,
            beta:                  beta,
            salvageRatioFishmeal:  salvageRatioFishmeal,
            salvageRatioBiogas:    salvageRatioBiogas
        });
    }

    /**
     * @dev Funds escrow — locks payment 
     *      at contract formation (T+0)
     */
    function fundEscrow(
        bytes32 orderID
    ) external payable onlyBuyer(orderID) {
        Order storage order = orders[orderID];
        
        require(
            order.status == OrderStatus.Created,
            "Order not in Created state"
        );
        require(
            msg.value == order.quantity 
                * order.unitPrice,
            "Incorrect escrow amount"
        );

        order.escrowValue = msg.value;
        order.status      = OrderStatus.Funded;

        emit EscrowFunded(
            orderID,
            msg.value,
            block.timestamp
        );
    }

    /**
     * @dev Updates order status to Shipped
     */
    function updateStatus(
        bytes32 orderID
    ) external onlySeller(orderID) {
        require(
            orders[orderID].status 
                == OrderStatus.Funded,
            "Order not funded"
        );
        orders[orderID].status = OrderStatus.Shipped;
    }

    // ─────────────────────────────────────
    // ALGORITHM 3: CIRCULAR ROUTING LOGIC
    // ─────────────────────────────────────

    /**
     * @dev Main evaluation function — called 
     *      by oracle after IoT + lab data 
     *      is verified on-chain
     *      Implements full PASS/PARTIAL/FAIL
     *      routing with circular logic
     */
    function evaluateAndSettle(
        bytes32 orderID,
        uint256 minutesAbove,
        uint256 excessDeg,
        string  memory batchType
    ) external onlyOracle {

        Order storage order = orders[orderID];
        SLAParams memory sla = slaParams[orderID];

        require(
            order.status == OrderStatus.Shipped 
            || order.status == OrderStatus.Received,
            "Invalid order state for evaluation"
        );

        // ── QI Computation ──────────────────
        // QI = 100 - alpha*minutesAbove 
        //         - beta*excessDeg
        uint256 qi;
        uint256 deduction = 
            (sla.alpha * minutesAbove) + 
            (sla.beta  * excessDeg);

        if (deduction >= 100) {
            qi = 0;
        } else {
            qi = 100 - deduction;
        }

        order.qiScore = qi;
        order.status  = OrderStatus.QualityAssessed;

        // Store batch type for routing decision
        lotRegistry[order.lotID].batchType = batchType;

        emit QualityAssessed(
            orderID,
            qi,
            qi >= PASS_THRESHOLD 
                ? QIOutcome.PASS 
                : qi >= PARTIAL_THRESHOLD 
                    ? QIOutcome.PARTIAL 
                    : QIOutcome.FAIL
        );

        // ── Routing Decision ─────────────────
        if (qi >= PASS_THRESHOLD) {
            _executePASS(orderID);

        } else if (qi >= PARTIAL_THRESHOLD) {
            _executePARTIAL(orderID, qi);

        } else {
            _executeFAIL(orderID, batchType, sla);
        }
    }

    /**
     * @dev PASS: Full escrow release to seller
     */
    function _executePASS(
        bytes32 orderID
    ) internal {
        Order storage order = orders[orderID];
        order.outcome = QIOutcome.PASS;
        order.status  = OrderStatus.Settled;

        uint256 amount = order.escrowValue;
        order.escrowValue = 0;

        (bool success, ) = payable(order.seller)
            .call{value: amount}("");
        require(success, "PASS payment failed");

        emit EscrowReleased(
            orderID,
            order.seller,
            amount,
            "PASS"
        );
    }

    /**
     * @dev PARTIAL: Proportional payment 
     *      based on QI score, no renegotiation
     */
    function _executePARTIAL(
        bytes32 orderID,
        uint256 qi
    ) internal {
        Order storage order = orders[orderID];
        order.outcome = QIOutcome.PARTIAL;
        order.status  = OrderStatus.Settled;

        uint256 proportionalPayment = 
            (order.escrowValue * qi) / 100;
        uint256 penalty = 
            order.escrowValue - proportionalPayment;

        order.escrowValue = 0;

        (bool success, ) = payable(order.seller)
            .call{value: proportionalPayment}("");
        require(success, "PARTIAL payment failed");

        emit PartialSettlement(
            orderID,
            order.seller,
            proportionalPayment,
            penalty
        );

        emit EscrowReleased(
            orderID,
            order.seller,
            proportionalPayment,
            "PARTIAL"
        );
    }

    /**
     * @dev FAIL: Withhold primary payment,
     *      calculate salvage value, trigger
     *      circular routing to valorization
     *      partner — all in single execution
     *      THIS IS THE CORE CONTRIBUTION
     *      OF ALGORITHM 3
     */
    function _executeFAIL(
        bytes32 orderID,
        string  memory batchType,
        SLAParams memory sla
    ) internal {
        Order storage order = orders[orderID];
        order.outcome = QIOutcome.FAIL;
        order.status  = OrderStatus.CircularRouted;

        emit PrimaryPaymentWithheld(
            orderID,
            order.escrowValue
        );

        // ── Step 1: Select valorization route ──
        ValorizationRoute route;
        uint256 salvageRatio;

        if (keccak256(bytes(batchType)) == 
            keccak256(bytes("PROTEIN_GRADE"))) {
            route        = ValorizationRoute
                            .FISHMEAL_PROCESSOR;
            salvageRatio = sla.salvageRatioFishmeal;
        } else {
            route        = ValorizationRoute
                            .BIOGAS_FACILITY;
            salvageRatio = sla.salvageRatioBiogas;
        }

        order.route = route;

        // ── Step 2: Calculate salvage value ────
        uint256 salvageValue = 
            (order.escrowValue * salvageRatio) / 100;
        uint256 penalty = 
            order.escrowValue - salvageValue;

        // ── Step 3: Action A + B + C ───────────
        // Action A: Withhold primary (already done)
        
        // Action B: Release salvage to seller
        order.escrowValue = 0;

        (bool salvagePaid, ) = payable(order.seller)
            .call{value: salvageValue}("");
        require(salvagePaid, 
            "Salvage payment failed");

        emit SalvagePaymentReleased(
            orderID,
            order.seller,
            salvageValue,
            route
        );

        // Action C: Trigger circular routing
        address partnerAddress = 
            _selectValorizationPartner(route);
        require(
            partnerAddress != address(0),
            "No active valorization partner"
        );

        bytes32 subOrderID = keccak256(
            abi.encodePacked(
                orderID,
                block.timestamp,
                partnerAddress
            )
        );

        order.subOrderID = subOrderID;

        emit CircularRoutingTriggered(
            orderID,
            subOrderID,
            partnerAddress,
            route,
            salvageValue
        );

        // ── Step 4: Update lot registry ────────
        lotRegistry[order.lotID].status = 
            "REDIRECTED_TO_VALORIZATION";
        lotRegistry[order.lotID].routingProof = 
            subOrderID;

        emit CircularRouteCompleted(
            order.lotID,
            orderID,
            route,
            block.timestamp
        );
    }

    /**
     * @dev Selects active valorization partner
     *      based on route type
     */
    function _selectValorizationPartner(
        ValorizationRoute route
    ) internal view returns (address) {
        for (uint i = 0; 
             i < valorizationPartners.length; 
             i++) {
            if (valorizationPartners[i].route 
                    == route && 
                valorizationPartners[i].isActive) {
                return valorizationPartners[i]
                    .partnerAddress;
            }
        }
        // Fallback: return first active partner
        for (uint i = 0; 
             i < valorizationPartners.length; 
             i++) {
            if (valorizationPartners[i].isActive) {
                return valorizationPartners[i]
                    .partnerAddress;
            }
        }
        return address(0);
    }

    // ─────────────────────────────────────
    // VIEW FUNCTIONS
    // ─────────────────────────────────────

    function getOrder(
        bytes32 orderID
    ) external view returns (Order memory) {
        return orders[orderID];
    }

    function getLotRecord(
        bytes32 lotID
    ) external view returns (LotRecord memory) {
        return lotRegistry[lotID];
    }

    function getValorizationPartners() 
        external view returns (
            ValorizationPartner[] memory
        ) {
        return valorizationPartners;
    }

    // ─────────────────────────────────────
    // FALLBACK
    // ─────────────────────────────────────

    receive() external payable {}
    fallback() external payable {}
}