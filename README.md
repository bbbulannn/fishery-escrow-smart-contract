## Contract Architecture

The four governance components described in the paper are implemented 
as a multi-contract Solidity file (`CircularEscrowFishery.sol`):

| Component (Paper) | Function in Contract |
|-------------------|----------------------|
| LotRegistry | `recordActivity()` — immutable provenance logging |
| Custody | `updateLocation()` — role-checked stakeholder transfers |
| QualitySLA | `createOrder()` — Quality Index computation |
| EscrowSettlement | `evaluateAndSettle()` — financial settlement + circular routing |
