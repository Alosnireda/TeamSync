# TeamSync: Decentralized Group Task Management

TeamSync is a decentralized application built on Stacks blockchain using Clarity smart contracts. It provides a robust platform for team coordination and group accountability through blockchain technology.

TeamSync allows teams to create and manage group tasks with built-in accountability mechanisms using cryptocurrency stakes. The system implements a democratic approach to task verification and includes features for dispute resolution and shared expense management.

## Features

- **Group Management**
  - Create groups with customizable stake requirements
  - Join existing groups by staking tokens
  - Track member participation and contributions

- **Task Management**
  - Create tasks with deadlines and point rewards
  - Democratic task completion verification
  - Automated point distribution system

- **Stake-Based Accountability**
  - Members stake STX tokens to participate
  - Economic incentives for active participation
  - Secure token management through smart contracts

- **Dispute Resolution**
  - Built-in dispute creation and resolution system
  - Voting mechanism for dispute settlement
  - Deadline-based resolution tracking

- **Expense Management**
  - Track shared group expenses
  - Approval system for expense verification
  - Status tracking for payment completion

## Smart Contract Functions

### Core Functions

1. `create-group`
   - Creates a new group with specified stake requirements
   - Parameters: name, required-stake, threshold
   - Returns: group-id

2. `join-group`
   - Allows users to join existing groups
   - Parameters: group-id
   - Requires: STX stake transfer

3. `create-task`
   - Creates new tasks within a group
   - Parameters: group-id, description, deadline, points
   - Returns: task-id

4. `vote-task`
   - Votes on task completion
   - Parameters: group-id, task-id
   - Handles automatic completion when threshold met

### Management Functions

5. `create-dispute`
   - Initiates dispute resolution process
   - Parameters: group-id, task-id, resolution-deadline

6. `create-expense`
   - Creates shared expense records
   - Parameters: group-id, description, amount

### Read-Only Functions

- `get-group-details`
- `get-member-details`
- `get-task-details`

## Error Handling

The contract includes comprehensive error handling for various scenarios:
- ERR-NOT-AUTHORIZED (u1)
- ERR-ALREADY-EXISTS (u2)
- ERR-DOESNT-EXIST (u3)
- ERR-INVALID-STAKE (u4)
- ERR-TASK-EXPIRED (u5)
- ERR-INSUFFICIENT-VOTES (u6)
- ERR-ALREADY-VOTED (u7)
- ERR-NOT-MEMBER (u8)

## Technical Requirements

- Stacks blockchain environment
- Clarity smart contract support
- STX token for staking functionality

## Example Usage

```clarity
;; Create a new group
(contract-call? .teamsync-core create-group u"Project Alpha" u1000 u75)

;; Join an existing group
(contract-call? .teamsync-core join-group u1)

;; Create a task
(contract-call? .teamsync-core create-task u1 u"Complete frontend" u100 u50)
```

## Security Considerations

- All stake transfers are handled securely through the contract
- Voting mechanisms prevent double-voting
- Threshold-based consensus for task completion
- Active member verification for all operations
- Deadline enforcement for tasks and disputes

## Development

### Prerequisites
- Clarity CLI tools
- Stacks blockchain development environment
- Node.js and NPM (for testing environment)

### Testing
1. Clone the repository
2. Install dependencies
3. Run test suite

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request