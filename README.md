# 📦 Courier Reputation Ledger

A transparent, immutable delivery history system built on Stacks blockchain that makes courier hiring safer and more trustworthy.

## 🎯 Overview

The Courier Reputation Ledger creates an immutable record of courier performance, allowing customers to make informed hiring decisions while providing couriers with verifiable proof of their delivery history and reputation.

## ✨ Features

### 🚚 For Couriers
- **Register** on the platform with stake requirement
- **Accept** delivery requests from customers  
- **Track** delivery progress through multiple stages
- **Build** immutable reputation through successful deliveries
- **Earn** based on performance and customer ratings

### 👥 For Customers
- **Create** delivery requests with package details
- **Track** real-time delivery status
- **Rate** courier performance after delivery
- **Browse** courier reputation scores before hiring
- **Dispute** deliveries when issues arise

### ⚖️ Platform Features
- **Immutable** delivery history for all participants
- **Community-driven** dispute resolution system
- **Stake-based** courier registration for accountability
- **Transparent** reputation scoring algorithm
- **Comprehensive** delivery tracking system

## 🛠️ Core Functions

### Courier Registration
```clarity
(register-courier "John Smith" "+1234567890")
```

### Creating Deliveries
```clarity
(create-delivery courier-principal "123 Main St" "456 Oak Ave" package-hash fee-amount)
```

### Delivery Workflow
```clarity
(accept-delivery delivery-id)
(mark-picked-up delivery-id)
(mark-delivered delivery-id)
(confirm-delivery delivery-id rating)
```

### Reputation Queries
```clarity
(get-courier-reputation courier-principal)
(get-courier-info courier-principal)
(calculate-courier-score courier-principal)
```

## 📊 Reputation System

Couriers build reputation through:
- **Success Rate**: Percentage of successfully completed deliveries
- **Customer Ratings**: 1-5 star ratings from customers
- **Delivery Volume**: Total number of completed deliveries
- **Dispute History**: Community-resolved disputes

**Composite Score**: 60% success rate + 40% average rating

## 🔐 Security Features

- **Stake Requirement**: Minimum 1 STX stake for courier registration
- **Escrow System**: Delivery fees held in contract until completion
- **Dispute Window**: 144 blocks (≈24 hours) for dispute initiation
- **Community Voting**: Registered couriers vote on disputes
- **Immutable Records**: All delivery history permanently recorded

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX for transactions

### Development Setup
```bash
clarinet check
clarinet test
```

### Deployment
```bash
clarinet deploy --testnet
```

## 📋 Contract Constants

- `MINIMUM_STAKE`: 1,000,000 µSTX (1 STX)
- `DISPUTE_WINDOW_BLOCKS`: 144 blocks
- `MAX_RATING`: 5 stars
- `MIN_RATING`: 1 star

## 🎮 Usage Examples

### Register as a Courier
```clarity
(contract-call? .courier-reputation-ledger register-courier "Alice Johnson" "+1555-0123")
```

### Create a Delivery Request
```clarity
(contract-call? .courier-reputation-ledger create-delivery 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 
  "123 Pickup Street, City, State" 
  "456 Delivery Avenue, City, State"
  0x1234567890abcdef1234567890abcdef12345678
  u500000)
```

### Check Courier Reputation
```clarity
(contract-call? .courier-reputation-ledger get-courier-reputation 
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

## 🏗️ Contract Architecture

The contract uses several key data structures:
- **Couriers Map**: Stores courier profiles and statistics
- **Deliveries Map**: Tracks all delivery requests and status
- **Dispute System**: Manages community-driven dispute resolution
- **History Tracking**: Links couriers and customers to their deliveries

## 🤝 Contributing

This is an open-source project. Feel free to submit issues and pull requests to improve the courier reputation system.

## 📄 License

MIT License - see LICENSE file for details

---

**Built with ❤️ on Stacks blockchain for a more transparent delivery ecosystem**
