;; TeamRewards Contract
;; Implements reward mechanisms for team achievements

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-ALREADY-CLAIMED (err u2))
(define-constant ERR-INSUFFICIENT-POINTS (err u3))
(define-constant ERR-INVALID-MILESTONE (err u4))
(define-constant ERR-NOT-ACTIVE (err u5))
(define-constant ERR-THRESHOLD-NOT-MET (err u6))

;; Constants
(define-constant REWARD-CYCLE-LENGTH u144) ;; ~1 day in blocks
(define-constant MIN-POINTS-FOR-REWARD u100)

;; Data Maps
(define-map RewardPools
    { group-id: uint }
    {
        total-rewards: uint,
        last-distribution: uint,
        total-distributed: uint,
        active: bool
    }
)

(define-map AchievementMilestones
    { group-id: uint, milestone-id: uint }
    {
        title: (string-utf8 100),
        description: (string-utf8 200),
        points-required: uint,
        reward-amount: uint,
        claimed-count: uint,
        active: bool
    }
)

(define-map MemberRewards
    { group-id: uint, member: principal }
    {
        total-rewards: uint,
        last-claim: uint,
        achievements-count: uint,
        highest-milestone: uint
    }
)

(define-map ClaimedMilestones
    { group-id: uint, milestone-id: uint, member: principal }
    { claimed: bool }
)

;; Data Variables
(define-data-var last-milestone-id uint u0)

;; Read-only functions
(define-read-only (get-reward-pool (group-id uint))
    (default-to 
        { 
            total-rewards: u0,
            last-distribution: u0,
            total-distributed: u0,
            active: false
        }
        (map-get? RewardPools { group-id: group-id })
    )
)

(define-read-only (get-milestone (group-id uint) (milestone-id uint))
    (map-get? AchievementMilestones { group-id: group-id, milestone-id: milestone-id })
)

(define-read-only (get-member-rewards (group-id uint) (member principal))
    (default-to
        {
            total-rewards: u0,
            last-claim: u0,
            achievements-count: u0,
            highest-milestone: u0
        }
        (map-get? MemberRewards { group-id: group-id, member: member })
    )
)

;; Private functions
(define-private (calculate-reward-share (points uint) (total-points uint) (pool-amount uint))
    (/ (* points pool-amount) total-points)
)

;; Public functions

;; Reward Pool Management
(define-public (initialize-reward-pool (group-id uint))
    (let 
        ((group (unwrap! (contract-call? .teamcore get-group-details group-id) ERR-NOT-AUTHORIZED)))
        (asserts! (is-eq (get creator group) tx-sender) ERR-NOT-AUTHORIZED)
        (ok (map-set RewardPools
            { group-id: group-id }
            {
                total-rewards: u0,
                last-distribution: block-height,
                total-distributed: u0,
                active: true
            }
        ))
    )
)

(define-public (fund-reward-pool (group-id uint) (amount uint))
    (let 
        ((pool (get-reward-pool group-id))
         (group (unwrap! (contract-call? .teamcore get-group-details group-id) ERR-NOT-AUTHORIZED)))
        (asserts! (get active pool) ERR-NOT-ACTIVE)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (ok (map-set RewardPools
            { group-id: group-id }
            (merge pool { 
                total-rewards: (+ (get total-rewards pool) amount)
            })
        ))
    )
)

;; Achievement Milestone Management
(define-public (create-milestone 
    (group-id uint)
    (title (string-utf8 100))
    (description (string-utf8 200))
    (points-required uint)
    (reward-amount uint))
    (let
        ((new-milestone-id (+ (var-get last-milestone-id) u1))
         (group (unwrap! (contract-call? .teamcore get-group-details group-id) ERR-NOT-AUTHORIZED)))
        (asserts! (is-eq (get creator group) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (> points-required u0) ERR-INVALID-MILESTONE)
        (var-set last-milestone-id new-milestone-id)
        (ok (map-set AchievementMilestones
            { group-id: group-id, milestone-id: new-milestone-id }
            {
                title: title,
                description: description,
                points-required: points-required,
                reward-amount: reward-amount,
                claimed-count: u0,
                active: true
            }
        ))
    )
)

;; Reward Claims
(define-public (claim-milestone-reward (group-id uint) (milestone-id uint))
    (let
        ((milestone (unwrap! (get-milestone group-id milestone-id) ERR-INVALID-MILESTONE))
         (member (unwrap! (contract-call? .teamcore get-member-details group-id tx-sender) ERR-NOT-AUTHORIZED))
         (member-rewards (get-member-rewards group-id tx-sender))
         (claimed (default-to { claimed: false } 
            (map-get? ClaimedMilestones { group-id: group-id, milestone-id: milestone-id, member: tx-sender }))))
        
        ;; Check requirements
        (asserts! (get active milestone) ERR-NOT-ACTIVE)
        (asserts! (not (get claimed claimed)) ERR-ALREADY-CLAIMED)
        (asserts! (>= (get points member) (get points-required milestone)) ERR-INSUFFICIENT-POINTS)
        
        ;; Update milestone claims
        (map-set AchievementMilestones
            { group-id: group-id, milestone-id: milestone-id }
            (merge milestone { claimed-count: (+ (get claimed-count milestone) u1) })
        )
        
        ;; Mark as claimed
        (map-set ClaimedMilestones
            { group-id: group-id, milestone-id: milestone-id, member: tx-sender }
            { claimed: true }
        )
        
        ;; Update member rewards
        (map-set MemberRewards
            { group-id: group-id, member: tx-sender }
            {
                total-rewards: (+ (get total-rewards member-rewards) (get reward-amount milestone)),
                last-claim: block-height,
                achievements-count: (+ (get achievements-count member-rewards) u1),
                highest-milestone: (if (> milestone-id (get highest-milestone member-rewards))
                                     milestone-id
                                     (get highest-milestone member-rewards))
            }
        )
        
        ;; Transfer reward
        (try! (as-contract (stx-transfer? 
            (get reward-amount milestone)
            tx-sender
            tx-sender)))
        
        (ok true)
    )
)

;; Periodic Reward Distribution
(define-public (distribute-rewards (group-id uint))
    (let
        ((pool (get-reward-pool group-id))
         (group (unwrap! (contract-call? .teamcore get-group-details group-id) ERR-NOT-AUTHORIZED)))
        (asserts! (get active pool) ERR-NOT-ACTIVE)
        (asserts! (>= (- block-height (get last-distribution pool)) REWARD-CYCLE-LENGTH) ERR-THRESHOLD-NOT-MET)
        (asserts! (>= (get total-points group) MIN-POINTS-FOR-REWARD) ERR-INSUFFICIENT-POINTS)
        
        ;; Update distribution timestamp
        (ok (map-set RewardPools
            { group-id: group-id }
            (merge pool {
                last-distribution: block-height,
                total-distributed: (+ (get total-distributed pool) (get total-rewards pool)),
                total-rewards: u0
            })
        ))
    )
)

;; Initialize contract
(begin
    (var-set last-milestone-id u0)
    (ok true)
)