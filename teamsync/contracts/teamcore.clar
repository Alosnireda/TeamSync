;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-ALREADY-EXISTS (err u2))
(define-constant ERR-DOESNT-EXIST (err u3))
(define-constant ERR-INVALID-STAKE (err u4))
(define-constant ERR-TASK-EXPIRED (err u5))
(define-constant ERR-INSUFFICIENT-VOTES (err u6))
(define-constant ERR-ALREADY-VOTED (err u7))
(define-constant ERR-NOT-MEMBER (err u8))

;; Data Variables
(define-map groups 
    { group-id: uint }
    {
        name: (string-utf8 50),
        creator: principal,
        required-stake: uint,
        member-count: uint,
        threshold: uint,
        total-points: uint,
        active: bool
    }
)

(define-map group-members
    { group-id: uint, member: principal }
    {
        staked-amount: uint,
        points: uint,
        joined-at: uint,
        active: bool
    }
)

(define-map tasks
    { group-id: uint, task-id: uint }
    {
        description: (string-utf8 200),
        deadline: uint,
        status: (string-utf8 20),
        creator: principal,
        points: uint,
        votes-required: uint,
        votes-received: uint
    }
)

(define-map task-votes
    { group-id: uint, task-id: uint, voter: principal }
    { voted: bool }
)

(define-map group-expenses
    { group-id: uint, expense-id: uint }
    {
        description: (string-utf8 100),
        amount: uint,
        status: (string-utf8 20),
        approvals: uint,
        paid: bool
    }
)

;; Data maps for dispute resolution
(define-map disputes
    { group-id: uint, dispute-id: uint }
    {
        task-id: uint,
        creator: principal,
        status: (string-utf8 20),
        resolution-deadline: uint,
        votes-for: uint,
        votes-against: uint
    }
)

;; Counter for IDs
(define-data-var last-group-id uint u0)
(define-data-var last-task-id uint u0)
(define-data-var last-expense-id uint u0)
(define-data-var last-dispute-id uint u0)

;; Read-only functions
(define-read-only (get-group-details (group-id uint))
    (map-get? groups { group-id: group-id })
)

(define-read-only (get-member-details (group-id uint) (member principal))
    (map-get? group-members { group-id: group-id, member: member })
)

(define-read-only (get-task-details (group-id uint) (task-id uint))
    (map-get? tasks { group-id: group-id, task-id: task-id })
)

;; Public functions
(define-public (create-group (name (string-utf8 50)) (required-stake uint) (threshold uint))
    (let
        ((new-group-id (+ (var-get last-group-id) u1)))
        (asserts! (> required-stake u0) ERR-INVALID-STAKE)
        (asserts! (and (>= threshold u0) (<= threshold u100)) ERR-INVALID-STAKE)
        (try! (stx-transfer? required-stake tx-sender (as-contract tx-sender)))
        (map-set groups
            { group-id: new-group-id }
            {
                name: name,
                creator: tx-sender,
                required-stake: required-stake,
                member-count: u1,
                threshold: threshold,
                total-points: u0,
                active: true
            }
        )
        (map-set group-members
            { group-id: new-group-id, member: tx-sender }
            {
                staked-amount: required-stake,
                points: u0,
                joined-at: block-height,
                active: true
            }
        )
        (var-set last-group-id new-group-id)
        (ok new-group-id)
    )
)

(define-public (join-group (group-id uint))
    (let
        ((group (unwrap! (get-group-details group-id) ERR-DOESNT-EXIST))
         (stake (get required-stake group)))
        (asserts! (not (is-some (get-member-details group-id tx-sender))) ERR-ALREADY-EXISTS)
        (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
        (map-set group-members
            { group-id: group-id, member: tx-sender }
            {
                staked-amount: stake,
                points: u0,
                joined-at: block-height,
                active: true
            }
        )
        (map-set groups
            { group-id: group-id }
            (merge group { member-count: (+ (get member-count group) u1) })
        )
        (ok true)
    )
)

(define-public (create-task 
    (group-id uint)
    (description (string-utf8 200))
    (deadline uint)
    (points uint))
    (let
        ((new-task-id (+ (var-get last-task-id) u1))
         (member (unwrap! (get-member-details group-id tx-sender) ERR-NOT-MEMBER))
         (group (unwrap! (get-group-details group-id) ERR-DOESNT-EXIST)))
        (asserts! (get active member) ERR-NOT-MEMBER)
        (asserts! (> deadline block-height) ERR-TASK-EXPIRED)
        (map-set tasks
            { group-id: group-id, task-id: new-task-id }
            {
                description: description,
                deadline: deadline,
                status: "active",
                creator: tx-sender,
                points: points,
                votes-required: (/ (* (get member-count group) (get threshold group)) u100),
                votes-received: u0
            }
        )
        (var-set last-task-id new-task-id)
        (ok new-task-id)
    )
)

(define-public (vote-task (group-id uint) (task-id uint))
    (let
        ((task (unwrap! (get-task-details group-id task-id) ERR-DOESNT-EXIST))
         (member (unwrap! (get-member-details group-id tx-sender) ERR-NOT-MEMBER))
         (has-voted (default-to { voted: false } (map-get? task-votes { group-id: group-id, task-id: task-id, voter: tx-sender }))))
        (asserts! (get active member) ERR-NOT-MEMBER)
        (asserts! (not (get voted has-voted)) ERR-ALREADY-VOTED)
        (asserts! (< block-height (get deadline task)) ERR-TASK-EXPIRED)
        
        (map-set task-votes
            { group-id: group-id, task-id: task-id, voter: tx-sender }
            { voted: true }
        )
        
        (map-set tasks
            { group-id: group-id, task-id: task-id }
            (merge task { votes-received: (+ (get votes-received task) u1) })
        )
        
        ;; Check if task is complete
        (if (>= (+ (get votes-received task) u1) (get votes-required task))
            (begin
                (try! (complete-task group-id task-id))
                (ok true)
            )
            (ok true)
        )
    )
)

(define-private (complete-task (group-id uint) (task-id uint))
    (let
        ((task (unwrap! (get-task-details group-id task-id) ERR-DOESNT-EXIST))
         (creator-details (unwrap! (get-member-details group-id (get creator task)) ERR-NOT-MEMBER)))
        (map-set tasks
            { group-id: group-id, task-id: task-id }
            (merge task { status: "completed" })
        )
        (map-set group-members
            { group-id: group-id, member: (get creator task) }
            (merge creator-details { points: (+ (get points creator-details) (get points task)) })
        )
        (ok true)
    )
)

(define-public (create-dispute 
    (group-id uint)
    (task-id uint)
    (resolution-deadline uint))
    (let
        ((new-dispute-id (+ (var-get last-dispute-id) u1))
         (member (unwrap! (get-member-details group-id tx-sender) ERR-NOT-MEMBER))
         (task (unwrap! (get-task-details group-id task-id) ERR-DOESNT-EXIST)))
        (asserts! (get active member) ERR-NOT-MEMBER)
        (asserts! (> resolution-deadline block-height) ERR-TASK-EXPIRED)
        
        (map-set disputes
            { group-id: group-id, dispute-id: new-dispute-id }
            {
                task-id: task-id,
                creator: tx-sender,
                status: "active",
                resolution-deadline: resolution-deadline,
                votes-for: u0,
                votes-against: u0
            }
        )
        (var-set last-dispute-id new-dispute-id)
        (ok new-dispute-id)
    )
)

(define-public (create-expense 
    (group-id uint)
    (description (string-utf8 100))
    (amount uint))
    (let
        ((new-expense-id (+ (var-get last-expense-id) u1))
         (member (unwrap! (get-member-details group-id tx-sender) ERR-NOT-MEMBER))
         (group (unwrap! (get-group-details group-id) ERR-DOESNT-EXIST)))
        (asserts! (get active member) ERR-NOT-MEMBER)
        (map-set group-expenses
            { group-id: group-id, expense-id: new-expense-id }
            {
                description: description,
                amount: amount,
                status: "pending",
                approvals: u0,
                paid: false
            }
        )
        (var-set last-expense-id new-expense-id)
        (ok new-expense-id)
    )
)

;; Initialize contract
(begin
    (var-set last-group-id u0)
    (var-set last-task-id u0)
    (var-set last-expense-id u0)
    (var-set last-dispute-id u0)
)