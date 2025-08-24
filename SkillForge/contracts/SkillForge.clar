;; SkillForge - Proven. Verified. Trusted.
;; A decentralized skill verification and certification platform
;; Features: Skill assessments, peer validation, credential management

;; ===================================
;; CONSTANTS AND ERROR CODES
;; ===================================

(define-constant ERR-NOT-AUTHORIZED (err u40))
(define-constant ERR-SKILL-NOT-FOUND (err u41))
(define-constant ERR-ALREADY-CERTIFIED (err u42))
(define-constant ERR-INSUFFICIENT-VALIDATORS (err u43))
(define-constant ERR-INVALID-SCORE (err u44))
(define-constant ERR-ASSESSMENT-EXPIRED (err u45))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-PASSING-SCORE u70)
(define-constant MIN-VALIDATORS u3)
(define-constant ASSESSMENT-DURATION u720) ;; ~5 days
(define-constant CERTIFICATION-FEE u500000) ;; 0.5 STX

;; ===================================
;; DATA VARIABLES
;; ===================================

(define-data-var platform-active bool true)
(define-data-var skill-counter uint u0)
(define-data-var assessment-counter uint u0)
(define-data-var platform-revenue uint u0)

;; ===================================
;; TOKEN DEFINITIONS
;; ===================================

;; Certification badges as NFTs
(define-non-fungible-token skill-badge uint)

;; ===================================
;; DATA MAPS
;; ===================================

;; Available skills for certification
(define-map skills
  uint
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    category: (string-ascii 32),
    difficulty-level: uint,
    total-certified: uint,
    active: bool,
    created-by: principal
  }
)

;; Skill assessments
(define-map assessments
  uint
  {
    candidate: principal,
    skill-id: uint,
    score: uint,
    validator-count: uint,
    created-at: uint,
    expires-at: uint,
    completed: bool,
    passed: bool
  }
)

;; Validator endorsements
(define-map validator-endorsements
  { assessment-id: uint, validator: principal }
  {
    score-given: uint,
    feedback: (string-ascii 128),
    timestamp: uint
  }
)

;; User certifications
(define-map user-certifications
  { user: principal, skill-id: uint }
  {
    certified: bool,
    score-achieved: uint,
    certification-date: uint,
    badge-id: uint,
    expires-at: uint
  }
)

;; Validator profiles
(define-map validators
  principal
  {
    active: bool,
    skills-validated: uint,
    reputation-score: uint,
    specializations: (list 5 uint)
  }
)

;; User profiles
(define-map user-profiles
  principal
  {
    total-certifications: uint,
    total-assessments: uint,
    average-score: uint,
    last-activity: uint
  }
)

;; ===================================
;; PRIVATE HELPER FUNCTIONS
;; ===================================

(define-private (is-contract-owner (user principal))
  (is-eq user CONTRACT-OWNER)
)

(define-private (is-validator (user principal))
  (match (map-get? validators user)
    validator-data
    (get active validator-data)
    false
  )
)

(define-private (is-assessment-active (assessment-id uint))
  (match (map-get? assessments assessment-id)
    assessment-data
    (and
      (not (get completed assessment-data))
      (<= burn-block-height (get expires-at assessment-data))
    )
    false
  )
)

(define-private (has-validator-endorsed (assessment-id uint) (validator principal))
  (is-some (map-get? validator-endorsements { assessment-id: assessment-id, validator: validator }))
)

(define-private (calculate-final-score (assessment-id uint) (total-validators uint))
  (if (> total-validators u0)
    (/ (fold + (list u1 u1 u1 u1 u1) u0) total-validators) ;; Simplified calculation
    u0
  )
)

;; ===================================
;; READ-ONLY FUNCTIONS
;; ===================================

(define-read-only (get-platform-info)
  {
    active: (var-get platform-active),
    total-skills: (var-get skill-counter),
    total-assessments: (var-get assessment-counter),
    platform-revenue: (var-get platform-revenue)
  }
)

(define-read-only (get-skill (skill-id uint))
  (map-get? skills skill-id)
)

(define-read-only (get-assessment (assessment-id uint))
  (map-get? assessments assessment-id)
)

(define-read-only (get-user-certification (user principal) (skill-id uint))
  (map-get? user-certifications { user: user, skill-id: skill-id })
)

(define-read-only (get-validator-profile (validator principal))
  (map-get? validators validator)
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles user)
)

(define-read-only (get-validator-endorsement (assessment-id uint) (validator principal))
  (map-get? validator-endorsements { assessment-id: assessment-id, validator: validator })
)

;; ===================================
;; ADMIN FUNCTIONS
;; ===================================

(define-public (toggle-platform (active bool))
  (begin
    (asserts! (is-contract-owner tx-sender) ERR-NOT-AUTHORIZED)
    (var-set platform-active active)
    (print { action: "platform-toggled", active: active })
    (ok true)
  )
)

(define-public (create-skill
  (name (string-ascii 64))
  (description (string-ascii 256))
  (category (string-ascii 32))
  (difficulty-level uint)
)
  (let (
    (skill-id (+ (var-get skill-counter) u1))
  )
    (asserts! (is-contract-owner tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= difficulty-level u5) ERR-INVALID-SCORE)
    
    ;; Create skill
    (map-set skills skill-id {
      name: name,
      description: description,
      category: category,
      difficulty-level: difficulty-level,
      total-certified: u0,
      active: true,
      created-by: tx-sender
    })
    
    (var-set skill-counter skill-id)
    (print { action: "skill-created", skill-id: skill-id, name: name, category: category })
    (ok skill-id)
  )
)

(define-public (add-validator (validator principal) (specializations (list 5 uint)))
  (begin
    (asserts! (is-contract-owner tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set validators validator {
      active: true,
      skills-validated: u0,
      reputation-score: u100,
      specializations: specializations
    })
    
    (print { action: "validator-added", validator: validator })
    (ok true)
  )
)

(define-public (withdraw-platform-revenue (amount uint))
  (begin
    (asserts! (is-contract-owner tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= amount (var-get platform-revenue)) ERR-INSUFFICIENT-VALIDATORS)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (var-set platform-revenue (- (var-get platform-revenue) amount))
    
    (print { action: "revenue-withdrawn", amount: amount })
    (ok true)
  )
)

;; ===================================
;; ASSESSMENT FUNCTIONS
;; ===================================

(define-public (start-assessment (skill-id uint))
  (let (
    (assessment-id (+ (var-get assessment-counter) u1))
    (skill-data (unwrap! (map-get? skills skill-id) ERR-SKILL-NOT-FOUND))
    (expires-at (+ burn-block-height ASSESSMENT-DURATION))
    (user-stats (default-to { total-certifications: u0, total-assessments: u0, average-score: u0, last-activity: u0 }
                            (map-get? user-profiles tx-sender)))
  )
    (asserts! (var-get platform-active) ERR-NOT-AUTHORIZED)
    (asserts! (get active skill-data) ERR-SKILL-NOT-FOUND)
    
    ;; Check if already certified
    (match (map-get? user-certifications { user: tx-sender, skill-id: skill-id })
      cert-data
      (asserts! (not (get certified cert-data)) ERR-ALREADY-CERTIFIED)
      true
    )
    
    ;; Transfer assessment fee
    (try! (stx-transfer? CERTIFICATION-FEE tx-sender (as-contract tx-sender)))
    
    ;; Create assessment
    (map-set assessments assessment-id {
      candidate: tx-sender,
      skill-id: skill-id,
      score: u0,
      validator-count: u0,
      created-at: burn-block-height,
      expires-at: expires-at,
      completed: false,
      passed: false
    })
    
    ;; Update user stats
    (map-set user-profiles tx-sender (merge user-stats {
      total-assessments: (+ (get total-assessments user-stats) u1),
      last-activity: burn-block-height
    }))
    
    ;; Update global stats
    (var-set assessment-counter assessment-id)
    (var-set platform-revenue (+ (var-get platform-revenue) CERTIFICATION-FEE))
    
    (print { action: "assessment-started", assessment-id: assessment-id, candidate: tx-sender, skill-id: skill-id })
    (ok assessment-id)
  )
)

(define-public (validate-assessment
  (assessment-id uint)
  (score uint)
  (feedback (string-ascii 128))
)
  (let (
    (assessment-data (unwrap! (map-get? assessments assessment-id) ERR-SKILL-NOT-FOUND))
    (validator-data (unwrap! (map-get? validators tx-sender) ERR-NOT-AUTHORIZED))
  )
    (asserts! (var-get platform-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-validator tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-assessment-active assessment-id) ERR-ASSESSMENT-EXPIRED)
    (asserts! (not (has-validator-endorsed assessment-id tx-sender)) ERR-ALREADY-CERTIFIED)
    (asserts! (<= score u100) ERR-INVALID-SCORE)
    
    ;; Record validator endorsement
    (map-set validator-endorsements { assessment-id: assessment-id, validator: tx-sender } {
      score-given: score,
      feedback: feedback,
      timestamp: burn-block-height
    })
    
    ;; Update assessment
    (map-set assessments assessment-id (merge assessment-data {
      validator-count: (+ (get validator-count assessment-data) u1)
    }))
    
    ;; Update validator stats
    (map-set validators tx-sender (merge validator-data {
      skills-validated: (+ (get skills-validated validator-data) u1),
      reputation-score: (+ (get reputation-score validator-data) u5)
    }))
    
    (print { action: "assessment-validated", assessment-id: assessment-id, validator: tx-sender, score: score })
    (ok true)
  )
)

(define-public (complete-assessment (assessment-id uint))
  (let (
    (assessment-data (unwrap! (map-get? assessments assessment-id) ERR-SKILL-NOT-FOUND))
    (skill-data (unwrap! (map-get? skills (get skill-id assessment-data)) ERR-SKILL-NOT-FOUND))
    (final-score (calculate-final-score assessment-id (get validator-count assessment-data)))
    (passed (>= final-score MIN-PASSING-SCORE))
    (badge-id (if passed (+ (var-get assessment-counter) u1000) u0))
    (user-stats (default-to { total-certifications: u0, total-assessments: u0, average-score: u0, last-activity: u0 }
                            (map-get? user-profiles (get candidate assessment-data))))
  )
    (asserts! (var-get platform-active) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get validator-count assessment-data) MIN-VALIDATORS) ERR-INSUFFICIENT-VALIDATORS)
    (asserts! (not (get completed assessment-data)) ERR-ALREADY-CERTIFIED)
    
    ;; Mark assessment as completed
    (map-set assessments assessment-id (merge assessment-data {
      score: final-score,
      completed: true,
      passed: passed
    }))
    
    ;; If passed, create certification and mint badge
    (if passed
      (begin
        (try! (nft-mint? skill-badge badge-id (get candidate assessment-data)))
        (map-set user-certifications { user: (get candidate assessment-data), skill-id: (get skill-id assessment-data) } {
          certified: true,
          score-achieved: final-score,
          certification-date: burn-block-height,
          badge-id: badge-id,
          expires-at: (+ burn-block-height u52560) ;; 1 year expiry
        })
        
        ;; Update skill stats
        (map-set skills (get skill-id assessment-data) (merge skill-data {
          total-certified: (+ (get total-certified skill-data) u1)
        }))
        
        ;; Update user stats
        (map-set user-profiles (get candidate assessment-data) (merge user-stats {
          total-certifications: (+ (get total-certifications user-stats) u1),
          average-score: (/ (+ (* (get average-score user-stats) (get total-certifications user-stats)) final-score)
                           (+ (get total-certifications user-stats) u1))
        }))
      )
      true
    )
    
    (print { action: "assessment-completed", assessment-id: assessment-id, passed: passed, score: final-score })
    (ok passed)
  )
)

(define-public (renew-certification (skill-id uint))
  (let (
    (cert-data (unwrap! (map-get? user-certifications { user: tx-sender, skill-id: skill-id }) ERR-SKILL-NOT-FOUND))
  )
    (asserts! (var-get platform-active) ERR-NOT-AUTHORIZED)
    (asserts! (get certified cert-data) ERR-SKILL-NOT-FOUND)
    
    ;; Transfer renewal fee
    (try! (stx-transfer? (/ CERTIFICATION-FEE u2) tx-sender (as-contract tx-sender)))
    
    ;; Renew certification
    (map-set user-certifications { user: tx-sender, skill-id: skill-id } (merge cert-data {
      expires-at: (+ burn-block-height u52560) ;; Extend 1 year
    }))
    
    ;; Update platform revenue
    (var-set platform-revenue (+ (var-get platform-revenue) (/ CERTIFICATION-FEE u2)))
    
    (print { action: "certification-renewed", user: tx-sender, skill-id: skill-id })
    (ok true)
  )
)

;; ===================================
;; INITIALIZATION
;; ===================================

(begin
  (map-set validators CONTRACT-OWNER { active: true, skills-validated: u0, reputation-score: u100, specializations: (list u1 u2 u3 u4 u5) })
  (print "SkillForge Platform Initialized")
  (print "Proven. Verified. Trusted.")
)