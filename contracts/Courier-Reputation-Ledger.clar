;; title: Courier-Reputation-Ledger
;; version: 1.0.0
;; summary: Immutable delivery history and reputation system for couriers
;; description: A transparent ledger for tracking courier performance and building trust

(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_COURIER_NOT_FOUND (err u101))
(define-constant ERR_DELIVERY_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_ALREADY_REGISTERED (err u104))
(define-constant ERR_INSUFFICIENT_STAKE (err u105))
(define-constant ERR_DELIVERY_ALREADY_CONFIRMED (err u106))
(define-constant ERR_DISPUTE_WINDOW_CLOSED (err u107))
(define-constant ERR_INVALID_RATING (err u108))
(define-constant ERR_BONUS_ALREADY_CLAIMED (err u109))
(define-constant ERR_INSUFFICIENT_BONUS_POOL (err u110))
(define-constant ERR_SCORE_TOO_LOW (err u111))
(define-constant ERR_COMMITMENT_NOT_FOUND (err u112))
(define-constant ERR_ALREADY_COMMITTED (err u113))
(define-constant ERR_COMMITMENT_EXPIRED (err u114))
(define-constant ERR_INVALID_TIME_WINDOW (err u115))
(define-constant ERR_COMMITMENT_NOT_ELIGIBLE (err u116))

(define-constant MINIMUM_STAKE u1000000)
(define-constant DISPUTE_WINDOW_BLOCKS u144)
(define-constant MAX_RATING u5)
(define-constant MIN_RATING u1)
(define-constant BONUS_THRESHOLD_SCORE u85)
(define-constant BONUS_POOL_PERCENTAGE u5)

(define-data-var next-delivery-id uint u1)
(define-data-var total-couriers uint u0)
(define-data-var total-deliveries uint u0)
(define-data-var bonus-pool uint u0)
(define-data-var next-commitment-id uint u1)

(define-map couriers 
  principal 
  {
    name: (string-ascii 50),
    phone: (string-ascii 20),
    registration-block: uint,
    total-deliveries: uint,
    successful-deliveries: uint,
    total-earnings: uint,
    stake-amount: uint,
    is-active: bool,
    average-rating: uint,
    last-bonus-block: uint
  }
)

(define-map deliveries 
  uint 
  {
    courier: principal,
    customer: principal,
    pickup-address: (string-ascii 200),
    delivery-address: (string-ascii 200),
    package-hash: (buff 32),
    fee: uint,
    status: (string-ascii 20),
    created-block: uint,
    completed-block: (optional uint),
    customer-rating: (optional uint),
    dispute-reason: (optional (string-ascii 500))
  }
)

(define-map courier-delivery-history 
  {courier: principal, delivery-id: uint} 
  bool
)

(define-map customer-orders 
  {customer: principal, delivery-id: uint} 
  bool
)

(define-map dispute-votes 
  {delivery-id: uint, voter: principal} 
  {vote: bool, block-voted: uint}
)

(define-map delivery-disputes 
  uint 
  {
    initiated-by: principal,
    dispute-block: uint,
    votes-for-courier: uint,
    votes-against-courier: uint,
    is-resolved: bool,
    resolution: (optional bool)
  }
)

(define-map time-commitments
  uint
  {
    delivery-id: uint,
    courier: principal,
    promised-blocks: uint,
    actual-blocks: (optional uint),
    commitment-type: (string-ascii 20),
    bonus-multiplier: uint,
    is-fulfilled: bool,
    is-claimed: bool,
    created-block: uint
  }
)

(define-map delivery-commitments
  uint
  { commitment-id: uint }
)

(define-map courier-commitment-stats
  principal
  {
    total-commitments: uint,
    fulfilled-commitments: uint,
    total-bonus-earned: uint,
    average-delivery-time: uint
  }
)

(define-public (register-courier (name (string-ascii 50)) (phone (string-ascii 20)))
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? couriers caller)) ERR_ALREADY_REGISTERED)
    (asserts! (>= (stx-get-balance caller) MINIMUM_STAKE) ERR_INSUFFICIENT_STAKE)
    
    (try! (stx-transfer? MINIMUM_STAKE caller (as-contract tx-sender)))
    
    (map-set couriers caller {
      name: name,
      phone: phone,
      registration-block: stacks-block-height,
      total-deliveries: u0,
      successful-deliveries: u0,
      total-earnings: u0,
      stake-amount: MINIMUM_STAKE,
      is-active: true,
      average-rating: u0,
      last-bonus-block: u0
    })
    
    (var-set total-couriers (+ (var-get total-couriers) u1))
    (ok caller)
  )
)

(define-public (create-delivery 
  (courier principal) 
  (pickup-address (string-ascii 200)) 
  (delivery-address (string-ascii 200))
  (package-hash (buff 32))
  (fee uint))
  (let ((delivery-id (var-get next-delivery-id))
        (caller tx-sender))
    
    (asserts! (is-some (map-get? couriers courier)) ERR_COURIER_NOT_FOUND)
    (asserts! (> fee u0) ERR_INVALID_STATUS)
    
    (let ((bonus-contribution (/ (* fee BONUS_POOL_PERCENTAGE) u100))
          (remaining-fee (- fee bonus-contribution)))
      (try! (stx-transfer? remaining-fee caller (as-contract tx-sender)))
      (var-set bonus-pool (+ (var-get bonus-pool) bonus-contribution)))
    
    (map-set deliveries delivery-id {
      courier: courier,
      customer: caller,
      pickup-address: pickup-address,
      delivery-address: delivery-address,
      package-hash: package-hash,
      fee: fee,
      status: "pending",
      created-block: stacks-block-height,
      completed-block: none,
      customer-rating: none,
      dispute-reason: none
    })
    
    (map-set courier-delivery-history {courier: courier, delivery-id: delivery-id} true)
    (map-set customer-orders {customer: caller, delivery-id: delivery-id} true)
    
    (var-set next-delivery-id (+ delivery-id u1))
    (var-set total-deliveries (+ (var-get total-deliveries) u1))
    
    (ok delivery-id)
  )
)

(define-public (accept-delivery (delivery-id uint))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender))
    
    (asserts! (is-eq caller (get courier delivery)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "pending") ERR_INVALID_STATUS)
    
    (map-set deliveries delivery-id 
      (merge delivery {status: "accepted"}))
    
    (ok true)
  )
)

(define-public (mark-picked-up (delivery-id uint))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender))
    
    (asserts! (is-eq caller (get courier delivery)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "accepted") ERR_INVALID_STATUS)
    
    (map-set deliveries delivery-id 
      (merge delivery {status: "picked-up"}))
    
    (ok true)
  )
)

(define-public (mark-delivered (delivery-id uint))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender))
    
    (asserts! (is-eq caller (get courier delivery)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "picked-up") ERR_INVALID_STATUS)
    
    (map-set deliveries delivery-id 
      (merge delivery {
        status: "delivered",
        completed-block: (some stacks-block-height)
      }))
    
    (ok true)
  )
)

(define-public (confirm-delivery (delivery-id uint) (rating uint))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender)
        (courier-principal (get courier delivery)))
    
    (asserts! (is-eq caller (get customer delivery)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "delivered") ERR_INVALID_STATUS)
    (asserts! (and (>= rating MIN_RATING) (<= rating MAX_RATING)) ERR_INVALID_RATING)
    (asserts! (is-none (get customer-rating delivery)) ERR_DELIVERY_ALREADY_CONFIRMED)
    
    (map-set deliveries delivery-id 
      (merge delivery {
        status: "confirmed",
        customer-rating: (some rating)
      }))
    
    (let ((bonus-contribution (/ (* (get fee delivery) BONUS_POOL_PERCENTAGE) u100))
          (courier-fee (- (get fee delivery) bonus-contribution)))
      (try! (as-contract (stx-transfer? courier-fee tx-sender courier-principal))))
    (try! (update-courier-stats courier-principal true rating))
    
    (ok true)
  )
)

(define-public (initiate-dispute (delivery-id uint) (reason (string-ascii 500)))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender))
    
    (asserts! (or (is-eq caller (get customer delivery)) 
                  (is-eq caller (get courier delivery))) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "delivered") ERR_INVALID_STATUS)
    (asserts! (is-none (map-get? delivery-disputes delivery-id)) ERR_INVALID_STATUS)
    
    (let ((completed-block (unwrap! (get completed-block delivery) ERR_INVALID_STATUS)))
      (asserts! (<= (- stacks-block-height completed-block) DISPUTE_WINDOW_BLOCKS) ERR_DISPUTE_WINDOW_CLOSED)
    )
    
    (map-set delivery-disputes delivery-id {
      initiated-by: caller,
      dispute-block: stacks-block-height,
      votes-for-courier: u0,
      votes-against-courier: u0,
      is-resolved: false,
      resolution: none
    })
    
    (map-set deliveries delivery-id 
      (merge delivery {
        status: "disputed",
        dispute-reason: (some reason)
      }))
    
    (ok true)
  )
)

(define-public (vote-on-dispute (delivery-id uint) (vote-for-courier bool))
  (let ((dispute (unwrap! (map-get? delivery-disputes delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender))
    
    (asserts! (is-some (map-get? couriers caller)) ERR_UNAUTHORIZED)
    (asserts! (not (get is-resolved dispute)) ERR_INVALID_STATUS)
    (asserts! (is-none (map-get? dispute-votes {delivery-id: delivery-id, voter: caller})) ERR_INVALID_STATUS)
    
    (map-set dispute-votes {delivery-id: delivery-id, voter: caller} {
      vote: vote-for-courier,
      block-voted: stacks-block-height
    })
    
    (if vote-for-courier
      (map-set delivery-disputes delivery-id 
        (merge dispute {votes-for-courier: (+ (get votes-for-courier dispute) u1)}))
      (map-set delivery-disputes delivery-id 
        (merge dispute {votes-against-courier: (+ (get votes-against-courier dispute) u1)}))
    )
    
    (ok true)
  )
)

(define-public (resolve-dispute (delivery-id uint))
  (let ((dispute (unwrap! (map-get? delivery-disputes delivery-id) ERR_DELIVERY_NOT_FOUND))
        (delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (total-votes (+ (get votes-for-courier dispute) (get votes-against-courier dispute))))
    
    (asserts! (>= total-votes u3) ERR_INVALID_STATUS)
    (asserts! (not (get is-resolved dispute)) ERR_INVALID_STATUS)
    
    (let ((courier-wins (> (get votes-for-courier dispute) (get votes-against-courier dispute)))
          (courier-principal (get courier delivery)))
      
      (if courier-wins
        (begin
          (try! (as-contract (stx-transfer? (get fee delivery) tx-sender courier-principal)))
          (try! (update-courier-stats courier-principal true u5))
          (map-set deliveries delivery-id 
            (merge delivery {status: "confirmed", customer-rating: (some u5)}))
        )
        (begin
          (try! (as-contract (stx-transfer? (get fee delivery) tx-sender (get customer delivery))))
          (try! (update-courier-stats courier-principal false u1))
          (map-set deliveries delivery-id 
            (merge delivery {status: "failed", customer-rating: (some u1)}))
        )
      )
      
      (map-set delivery-disputes delivery-id 
        (merge dispute {
          is-resolved: true,
          resolution: (some courier-wins)
        }))
      
      (ok courier-wins)
    )
  )
)

(define-public (claim-bonus)
  (let ((caller tx-sender)
        (courier-data (unwrap! (map-get? couriers caller) ERR_COURIER_NOT_FOUND))
        (courier-score (unwrap! (calculate-courier-score caller) ERR_COURIER_NOT_FOUND)))
    
    (asserts! (get is-active courier-data) ERR_UNAUTHORIZED)
    (asserts! (>= courier-score BONUS_THRESHOLD_SCORE) ERR_SCORE_TOO_LOW)
    (asserts! (> (var-get bonus-pool) u0) ERR_INSUFFICIENT_BONUS_POOL)
    (asserts! (> (- stacks-block-height (get last-bonus-block courier-data)) u144) ERR_BONUS_ALREADY_CLAIMED)
    
    (let ((bonus-amount (calculate-bonus courier-score)))
      (asserts! (>= (var-get bonus-pool) bonus-amount) ERR_INSUFFICIENT_BONUS_POOL)
      
      (try! (as-contract (stx-transfer? bonus-amount tx-sender caller)))
      (var-set bonus-pool (- (var-get bonus-pool) bonus-amount))
      
      (map-set couriers caller 
        (merge courier-data {last-bonus-block: stacks-block-height}))
      
      (ok bonus-amount)
    )
  )
)

(define-public (deactivate-courier)
  (let ((caller tx-sender)
        (courier-data (unwrap! (map-get? couriers caller) ERR_COURIER_NOT_FOUND)))
    
    (asserts! (get is-active courier-data) ERR_INVALID_STATUS)
    
    (map-set couriers caller 
      (merge courier-data {is-active: false}))
    
    (try! (as-contract (stx-transfer? (get stake-amount courier-data) tx-sender caller)))
    
    (ok true)
  )
)

(define-private (update-courier-stats (courier principal) (successful bool) (rating uint))
  (let ((courier-data (unwrap! (map-get? couriers courier) ERR_COURIER_NOT_FOUND)))
    
    (let ((new-total (+ (get total-deliveries courier-data) u1))
          (new-successful (if successful 
                             (+ (get successful-deliveries courier-data) u1)
                             (get successful-deliveries courier-data)))
          (new-earnings (if successful 
                           (+ (get total-earnings courier-data) u1)
                           (get total-earnings courier-data)))
          (current-avg (get average-rating courier-data))
          (new-avg (if (is-eq current-avg u0)
                      rating
                      (/ (+ (* current-avg (get total-deliveries courier-data)) rating) new-total))))
      
      (map-set couriers courier 
        (merge courier-data {
          total-deliveries: new-total,
          successful-deliveries: new-successful,
          total-earnings: new-earnings,
          average-rating: new-avg
        }))
      
      (ok true)
    )
  )
)

(define-private (calculate-bonus (score uint))
  (let ((base-bonus (/ (var-get bonus-pool) u10)))
    (if (>= score u95)
      (* base-bonus u3)
      (if (>= score u90)
        (* base-bonus u2)
        base-bonus))))

(define-read-only (get-courier-info (courier principal))
  (map-get? couriers courier)
)

(define-read-only (get-delivery-info (delivery-id uint))
  (map-get? deliveries delivery-id)
)

(define-read-only (get-courier-reputation (courier principal))
  (match (map-get? couriers courier)
    courier-data (let ((total (get total-deliveries courier-data))
                       (successful (get successful-deliveries courier-data)))
                   (ok {
                     success-rate: (if (> total u0) 
                                     (/ (* successful u100) total) 
                                     u0),
                     average-rating: (get average-rating courier-data),
                     total-deliveries: total,
                     is-active: (get is-active courier-data)
                   }))
    ERR_COURIER_NOT_FOUND
    )
)

(define-read-only (can-claim-bonus (courier principal))
  (match (map-get? couriers courier)
    courier-data (match (calculate-courier-score courier)
                    score (ok {
                      eligible: (and (get is-active courier-data)
                                   (>= score BONUS_THRESHOLD_SCORE)
                                   (> (var-get bonus-pool) u0)
                                   (> (- stacks-block-height (get last-bonus-block courier-data)) u144)),
                      score: score,
                      bonus-amount: (calculate-bonus score),
                      blocks-until-eligible: (if (> (- stacks-block-height (get last-bonus-block courier-data)) u144)
                                               u0
                                               (- u144 (- stacks-block-height (get last-bonus-block courier-data))))
                    })
                    err ERR_COURIER_NOT_FOUND)
    ERR_COURIER_NOT_FOUND
  )
)

(define-read-only (get-bonus-pool)
  (var-get bonus-pool)
)

(define-read-only (get-courier-delivery-ids (courier principal) (limit uint) (offset uint))
  (let ((delivery-ids (list)))
    (fold check-courier-delivery 
          (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20)
          {courier: courier, limit: limit, offset: offset, current: u0, results: (list)})
  )
)

(define-private (check-courier-delivery (delivery-id uint) (state {courier: principal, limit: uint, offset: uint, current: uint, results: (list 20 uint)}))
  (let ((courier (get courier state))
        (current-count (get current state))
        (results (get results state)))
    
    (if (and (< (len results) (get limit state))
             (>= current-count (get offset state))
             (default-to false (map-get? courier-delivery-history {courier: courier, delivery-id: delivery-id})))
      {
        courier: courier,
        limit: (get limit state),
        offset: (get offset state),
        current: (+ current-count u1),
        results: (unwrap-panic (as-max-len? (append results delivery-id) u20))
      }
      {
        courier: courier,
        limit: (get limit state),
        offset: (get offset state),
        current: (+ current-count u1),
        results: results
      }
    )
  )
)

(define-read-only (get-customer-orders (customer principal) (limit uint) (offset uint))
  (let ((order-ids (list)))
    (fold check-customer-order 
          (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20)
          {customer: customer, limit: limit, offset: offset, current: u0, results: (list)})
  )
)

(define-private (check-customer-order (delivery-id uint) (state {customer: principal, limit: uint, offset: uint, current: uint, results: (list 20 uint)}))
  (let ((customer (get customer state))
        (current-count (get current state))
        (results (get results state)))
    
    (if (and (< (len results) (get limit state))
             (>= current-count (get offset state))
             (default-to false (map-get? customer-orders {customer: customer, delivery-id: delivery-id})))
      {
        customer: customer,
        limit: (get limit state),
        offset: (get offset state),
        current: (+ current-count u1),
        results: (unwrap-panic (as-max-len? (append results delivery-id) u20))
      }
      {
        customer: customer,
        limit: (get limit state),
        offset: (get offset state),
        current: (+ current-count u1),
        results: results
      }
    )
  )
)

(define-read-only (get-platform-stats)
  (ok {
    total-couriers: (var-get total-couriers),
    total-deliveries: (var-get total-deliveries),
    next-delivery-id: (var-get next-delivery-id),
    bonus-pool: (var-get bonus-pool)
  })
)

(define-read-only (get-dispute-info (delivery-id uint))
  (map-get? delivery-disputes delivery-id)
)

(define-read-only (can-dispute (delivery-id uint))
  (match (map-get? deliveries delivery-id)
    delivery (match (get completed-block delivery)
               completed-block (and (is-eq (get status delivery) "delivered")
                                   (<= (- stacks-block-height completed-block) DISPUTE_WINDOW_BLOCKS)
                                   (is-none (map-get? delivery-disputes delivery-id)))
               false)
    false
  )
)

(define-read-only (is-courier-registered (courier principal))
  (is-some (map-get? couriers courier))
)

(define-read-only (get-delivery-status (delivery-id uint))
  (match (map-get? deliveries delivery-id)
    delivery (ok (get status delivery))
    ERR_DELIVERY_NOT_FOUND
  )
)

(define-read-only (calculate-courier-score (courier principal))
  (match (map-get? couriers courier)
    courier-data (let ((total (get total-deliveries courier-data))
                       (successful (get successful-deliveries courier-data))
                       (avg-rating (get average-rating courier-data)))
                   (ok (if (> total u0)
                         (+ (/ (* successful u60) total) 
                            (/ (* avg-rating u40) MAX_RATING))
                         u0)))
    ERR_COURIER_NOT_FOUND
  )
)

(define-public (create-time-commitment
  (delivery-id uint)
  (promised-blocks uint)
  (commitment-type (string-ascii 20)))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (caller tx-sender)
        (commitment-id (var-get next-commitment-id)))
    
    (asserts! (is-eq caller (get courier delivery)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "accepted") ERR_INVALID_STATUS)
    (asserts! (is-none (map-get? delivery-commitments delivery-id)) ERR_ALREADY_COMMITTED)
    (asserts! (> promised-blocks u0) ERR_INVALID_TIME_WINDOW)
    (asserts! (<= promised-blocks u1440) ERR_INVALID_TIME_WINDOW)
    
    (let ((bonus-multiplier (calculate-commitment-multiplier promised-blocks)))
      (map-set time-commitments commitment-id {
        delivery-id: delivery-id,
        courier: caller,
        promised-blocks: promised-blocks,
        actual-blocks: none,
        commitment-type: commitment-type,
        bonus-multiplier: bonus-multiplier,
        is-fulfilled: false,
        is-claimed: false,
        created-block: stacks-block-height
      })
      
      (map-set delivery-commitments delivery-id { commitment-id: commitment-id })
      
      (let ((courier-stats (default-to
                             { total-commitments: u0, fulfilled-commitments: u0, total-bonus-earned: u0, average-delivery-time: u0 }
                             (map-get? courier-commitment-stats caller))))
        (map-set courier-commitment-stats caller
          (merge courier-stats { total-commitments: (+ (get total-commitments courier-stats) u1) })))
      
      (var-set next-commitment-id (+ commitment-id u1))
      (ok commitment-id)
    )
  )
)

(define-public (finalize-commitment (delivery-id uint))
  (let ((delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND))
        (commitment-data (unwrap! (map-get? delivery-commitments delivery-id) ERR_COMMITMENT_NOT_FOUND))
        (commitment-id (get commitment-id commitment-data))
        (commitment (unwrap! (map-get? time-commitments commitment-id) ERR_COMMITMENT_NOT_FOUND))
        (caller tx-sender))
    
    (asserts! (is-eq caller (get courier commitment)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status delivery) "confirmed") ERR_INVALID_STATUS)
    (asserts! (not (get is-fulfilled commitment)) ERR_INVALID_STATUS)
    
    (let ((completed-block (unwrap! (get completed-block delivery) ERR_INVALID_STATUS))
          (created-block (get created-block delivery))
          (actual-time (- completed-block created-block))
          (promised-blocks (get promised-blocks commitment))
          (is-fulfilled (<= actual-time promised-blocks)))
      
      (map-set time-commitments commitment-id
        (merge commitment {
          actual-blocks: (some actual-time),
          is-fulfilled: is-fulfilled
        }))
      
      (let ((courier-stats (unwrap! (map-get? courier-commitment-stats caller) ERR_COURIER_NOT_FOUND))
            (new-fulfilled (if is-fulfilled (+ (get fulfilled-commitments courier-stats) u1) (get fulfilled-commitments courier-stats)))
            (total-comms (get total-commitments courier-stats))
            (old-avg (get average-delivery-time courier-stats))
            (new-avg (if (is-eq old-avg u0)
                       actual-time
                       (/ (+ (* old-avg (- total-comms u1)) actual-time) total-comms))))
        
        (map-set courier-commitment-stats caller
          (merge courier-stats {
            fulfilled-commitments: new-fulfilled,
            average-delivery-time: new-avg
          })))
      
      (ok is-fulfilled)
    )
  )
)

(define-public (claim-commitment-bonus (commitment-id uint))
  (let ((commitment (unwrap! (map-get? time-commitments commitment-id) ERR_COMMITMENT_NOT_FOUND))
        (caller tx-sender)
        (delivery-id (get delivery-id commitment))
        (delivery (unwrap! (map-get? deliveries delivery-id) ERR_DELIVERY_NOT_FOUND)))
    
    (asserts! (is-eq caller (get courier commitment)) ERR_UNAUTHORIZED)
    (asserts! (get is-fulfilled commitment) ERR_COMMITMENT_NOT_ELIGIBLE)
    (asserts! (not (get is-claimed commitment)) ERR_BONUS_ALREADY_CLAIMED)
    (asserts! (is-eq (get status delivery) "confirmed") ERR_INVALID_STATUS)
    
    (let ((base-fee (get fee delivery))
          (bonus-multiplier (get bonus-multiplier commitment))
          (bonus-amount (/ (* base-fee bonus-multiplier) u100)))
      
      (asserts! (>= (var-get bonus-pool) bonus-amount) ERR_INSUFFICIENT_BONUS_POOL)
      
      (try! (as-contract (stx-transfer? bonus-amount tx-sender caller)))
      (var-set bonus-pool (- (var-get bonus-pool) bonus-amount))
      
      (map-set time-commitments commitment-id
        (merge commitment { is-claimed: true }))
      
      (let ((courier-stats (unwrap! (map-get? courier-commitment-stats caller) ERR_COURIER_NOT_FOUND)))
        (map-set courier-commitment-stats caller
          (merge courier-stats { total-bonus-earned: (+ (get total-bonus-earned courier-stats) bonus-amount) })))
      
      (ok bonus-amount)
    )
  )
)

(define-private (calculate-commitment-multiplier (promised-blocks uint))
  (if (<= promised-blocks u72)
    u20
    (if (<= promised-blocks u144)
      u15
      (if (<= promised-blocks u288)
        u10
        u5)))
)

(define-read-only (get-commitment-info (commitment-id uint))
  (map-get? time-commitments commitment-id)
)

(define-read-only (get-delivery-commitment (delivery-id uint))
  (match (map-get? delivery-commitments delivery-id)
    commitment-data (map-get? time-commitments (get commitment-id commitment-data))
    none
  )
)

(define-read-only (get-courier-commitment-stats (courier principal))
  (map-get? courier-commitment-stats courier)
)

(define-read-only (calculate-commitment-fulfillment-rate (courier principal))
  (match (map-get? courier-commitment-stats courier)
    stats (let ((total (get total-commitments stats))
                (fulfilled (get fulfilled-commitments stats)))
            (ok {
              total-commitments: total,
              fulfilled-commitments: fulfilled,
              fulfillment-rate: (if (> total u0)
                                  (/ (* fulfilled u100) total)
                                  u0),
              average-delivery-time: (get average-delivery-time stats),
              total-bonus-earned: (get total-bonus-earned stats)
            }))
    (ok {
      total-commitments: u0,
      fulfilled-commitments: u0,
      fulfillment-rate: u0,
      average-delivery-time: u0,
      total-bonus-earned: u0
    })
  )
)

(define-read-only (estimate-commitment-bonus (delivery-id uint) (promised-blocks uint))
  (match (map-get? deliveries delivery-id)
    delivery (let ((base-fee (get fee delivery))
                   (multiplier (calculate-commitment-multiplier promised-blocks))
                   (estimated-bonus (/ (* base-fee multiplier) u100)))
              (ok {
                promised-blocks: promised-blocks,
                bonus-multiplier: multiplier,
                estimated-bonus: estimated-bonus,
                base-fee: base-fee
              }))
    ERR_DELIVERY_NOT_FOUND
  )
)

(define-read-only (can-create-commitment (delivery-id uint))
  (match (map-get? deliveries delivery-id)
    delivery (and (is-eq (get status delivery) "accepted")
                  (is-none (map-get? delivery-commitments delivery-id)))
    false
  )
)

(define-read-only (get-commitment-performance (commitment-id uint))
  (match (map-get? time-commitments commitment-id)
    commitment (match (get actual-blocks commitment)
                 actual (ok {
                          promised-blocks: (get promised-blocks commitment),
                          actual-blocks: actual,
                          difference: (if (> actual (get promised-blocks commitment))
                                       (- actual (get promised-blocks commitment))
                                       u0),
                          is-fulfilled: (get is-fulfilled commitment),
                          performance-percentage: (if (> actual u0)
                                                    (/ (* (get promised-blocks commitment) u100) actual)
                                                    u0)
                        })
                 (ok {
                      promised-blocks: (get promised-blocks commitment),
                      actual-blocks: u0,
                      difference: u0,
                      is-fulfilled: false,
                      performance-percentage: u0
                    }))
    ERR_COMMITMENT_NOT_FOUND
  )
)
