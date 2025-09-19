;; p2p-network-scraper
;; A decentralized network data collection and analysis smart contract
;; This contract enables community-driven network data gathering and validation

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-DATA (err u101))
(define-constant ERR-DATA-ALREADY-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-STAKE (err u103))
(define-constant ERR-VERIFICATION-FAILED (err u104))

;; Stake and reward constants
(define-constant MIN-STAKE u1000) ;; Minimum STX to participate
(define-constant REWARD-PERCENTAGE u10) ;; 10% reward for valid data submissions

;; Data status options
(define-constant STATUS-PENDING u1)
(define-constant STATUS-VERIFIED u2)
(define-constant STATUS-DISPUTED u3)

;; Data maps
(define-map network-data-submissions
  { submission-id: uint }
  {
    submitter: principal,
    data-type: (string-utf8 50),
    network-identifier: (string-utf8 100),
    raw-data: (string-utf8 1000),
    stake-amount: uint,
    status: uint,
    created-at: uint,
    verified-by: (optional principal)
  }
)

(define-map data-verifications
  { submission-id: uint }
  {
    verifier: principal,
    verification-result: bool,
    verification-comment: (optional (string-utf8 200)),
    verified-at: uint
  }
)

(define-map user-reputation
  { user: principal }
  {
    total-submissions: uint,
    successful-submissions: uint,
    reputation-score: uint
  }
)

;; Counters for ID generation
(define-data-var submission-id-counter uint u1)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Private functions

;; Generate a new submission ID
(define-private (generate-submission-id)
  (let ((current-id (var-get submission-id-counter)))
    (var-set submission-id-counter (+ current-id u1))
    current-id
  )
)

;; Check if caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Calculate reputation score
(define-private (calculate-reputation-score (total-submissions uint) (successful-submissions uint))
  (if (is-eq total-submissions u0)
    u50 ;; Default neutral score
    (/ (* successful-submissions u100) total-submissions)
  )
)

;; Read-only functions

;; Get network data submission details
(define-read-only (get-submission (submission-id uint))
  (map-get? network-data-submissions { submission-id: submission-id })
)

;; Public functions

;; Submit network data
(define-public (submit-network-data
  (data-type (string-utf8 50))
  (network-identifier (string-utf8 100))
  (raw-data (string-utf8 1000))
  (stake-amount uint)
)
  (let (
    (new-submission-id (generate-submission-id))
    (user-reputation (default-to 
      { total-submissions: u0, successful-submissions: u0, reputation-score: u50 } 
      (map-get? user-reputation { user: tx-sender })
    ))
  )
    ;; Validate stake amount
    (asserts! (>= stake-amount MIN-STAKE) ERR-INSUFFICIENT-STAKE)
    
    ;; Transfer stake to contract
    (unwrap! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)) ERR-INSUFFICIENT-STAKE)
    
    ;; Create submission record
    (map-set network-data-submissions
      { submission-id: new-submission-id }
      {
        submitter: tx-sender,
        data-type: data-type,
        network-identifier: network-identifier,
        raw-data: raw-data,
        stake-amount: stake-amount,
        status: STATUS-PENDING,
        created-at: block-height,
        verified-by: none
      }
    )
    
    ;; Update user reputation
    (map-set user-reputation
      { user: tx-sender }
      {
        total-submissions: (+ (get total-submissions user-reputation) u1),
        successful-submissions: (get successful-submissions user-reputation),
        reputation-score: (calculate-reputation-score 
          (+ (get total-submissions user-reputation) u1)
          (get successful-submissions user-reputation)
        )
      }
    )
    
    (ok new-submission-id)
  )
)

;; Verify submitted network data
(define-public (verify-network-data
  (submission-id uint)
  (is-valid bool)
  (verification-comment (optional (string-utf8 200)))
)
  (let (
    (submission (unwrap! (map-get? network-data-submissions { submission-id: submission-id }) ERR-INVALID-DATA))
    (stake-amount (get stake-amount submission))
    (reward-amount (/ (* stake-amount REWARD-PERCENTAGE) u100))
  )
    ;; Prevent self-verification
    (asserts! (not (is-eq tx-sender (get submitter submission))) ERR-NOT-AUTHORIZED)
    
    ;; Create verification record
    (map-set data-verifications
      { submission-id: submission-id }
      {
        verifier: tx-sender,
        verification-result: is-valid,
        verification-comment: verification-comment,
        verified-at: block-height
      }
    )
    
    ;; Update submission status
    (map-set network-data-submissions
      { submission-id: submission-id }
      (merge submission {
        status: (if is-valid STATUS-VERIFIED STATUS-DISPUTED),
        verified-by: (some tx-sender)
      })
    )
    
    ;; Reward mechanism
    (if is-valid
      (begin
        ;; Return original stake and reward to submitter
        (as-contract
          (begin
            (unwrap! (stx-transfer? stake-amount tx-sender (get submitter submission)) ERR-INVALID-DATA)
            (unwrap! (stx-transfer? reward-amount tx-sender tx-sender) ERR-INVALID-DATA)
          )
        )
        
        ;; Update submitter's reputation
        (let ((submitter-reputation (default-to 
          { total-submissions: u0, successful-submissions: u0, reputation-score: u50 } 
          (map-get? user-reputation { user: (get submitter submission) })
        )))
          (map-set user-reputation
            { user: (get submitter submission) }
            {
              total-submissions: (get total-submissions submitter-reputation),
              successful-submissions: (+ (get successful-submissions submitter-reputation) u1),
              reputation-score: (calculate-reputation-score 
                (get total-submissions submitter-reputation)
                (+ (get successful-submissions submitter-reputation) u1)
              )
            }
          )
        )
      )
      ;; If invalid, transfer stake to verifier
      (as-contract
        (unwrap! (stx-transfer? stake-amount tx-sender tx-sender) ERR-INVALID-DATA)
      )
    )
    
    (ok true)
  )
)

;; Administrative functions

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)