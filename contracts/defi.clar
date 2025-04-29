;; DeFiNavigator Smart Contract
;; Delivers real-time financial data, currency conversions, rate calculations, and detailed reporting

;; Response codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-PRICE-UNAVAILABLE (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-PRICE-OUT-OF-RANGE (err u104))
(define-constant ERR-UNSUPPORTED-ASSET (err u105))
(define-constant ERR-INVALID-DISCOUNT (err u106))
(define-constant ERR-REFUND-REJECTED (err u107))
(define-constant ERR-INVALID-PERIOD (err u108))
(define-constant ERR-TRANSFER-FAILED (err u109))
(define-constant ERR-INVALID-PARAMETER (err u110)) ;; New response code for input validation

;; System variables
(define-data-var admin principal tx-sender)
(define-data-var minimum-threshold uint u100) ;; Minimum calculable amount in base asset

;; Valid asset list
(define-data-var supported-assets (list 20 (string-ascii 10)) (list ))

;; Price data (scaled by 1e8)
(define-map asset-prices
    { asset-symbol: (string-ascii 10) }
    { price-value: uint,
      last-updated: uint,
      is-active: bool }
)

;; Fee tiers with graduated levels
(define-map fee-tiers
    { fee-type: (string-ascii 24) }
    {
        tier-structure: (list 10 {
            value-threshold: uint,
            fee-percentage: uint,
            tier-notes: (string-ascii 64)
        }),
        reference-asset: (string-ascii 10),
        tier-update-time: uint
    }
)

;; Discount configuration
(define-map discount-types
    { discount-code: (string-ascii 10) }
    {
        discount-label: (string-ascii 64),
        max-discount-value: uint,
        discount-rate: uint,
        approval-required: bool
    }
)

;; User records with comprehensive tracking
(define-map client-profiles
    principal
    {
        total-fees-paid: uint,
        total-refunds-received: uint,
        latest-transaction: uint,
        client-tier: (string-ascii 24),
        applied-discounts: (list 20 {
            discount-code: (string-ascii 10),
            discount-value: uint,
            discount-approved: bool
        }),
        transaction-history: (list 50 {
            transaction-value: uint,
            timestamp: uint,
            transaction-asset: (string-ascii 10)
        })
    }
)

;; Helper function to check if an asset is supported
(define-private (is-supported-asset (asset (string-ascii 10)))
    (is-some (index-of (var-get supported-assets) asset))
)

;; Helper function to check if discount code exists
(define-private (is-valid-discount-code (discount-code (string-ascii 10)))
    (is-some (map-get? discount-types { discount-code: discount-code }))
)

;; Read-only functions for data retrieval
(define-read-only (get-client-profile (client principal))
    (map-get? client-profiles client)
)

(define-read-only (get-fee-tier-info (fee-type (string-ascii 24)))
    (map-get? fee-tiers { fee-type: fee-type })
)

(define-read-only (get-asset-price (asset-symbol (string-ascii 10)))
    (map-get? asset-prices { asset-symbol: asset-symbol })
)

(define-read-only (get-discount-info (discount-code (string-ascii 10)))
    (map-get? discount-types { discount-code: discount-code })
)

;; Asset conversion utility
(define-read-only (convert-asset-value (amount uint) (from-asset (string-ascii 10)) (to-asset (string-ascii 10)))
    (let (
        (source-price (unwrap! (get-asset-price from-asset) ERR-UNSUPPORTED-ASSET))
        (target-price (unwrap! (get-asset-price to-asset) ERR-UNSUPPORTED-ASSET))
    )
        (ok (/ (* amount (get price-value target-price)) (get price-value source-price)))
    )
)

(define-read-only (calculate-tiered-fee (input-amount uint) (fee-type (string-ascii 24)))
    (match (map-get? fee-tiers { fee-type: fee-type })
        tier-data
        (let ((total-calculated u0))
            (ok (fold process-tier-calculation 
                (get tier-structure tier-data)
                { remaining-value: input-amount, cumulative-result: u0 })))
        ERR-PRICE-UNAVAILABLE
    )
)

;; Helper for tiered calculation
(define-private (process-tier-calculation 
    (tier { value-threshold: uint, fee-percentage: uint, tier-notes: (string-ascii 64) })
    (calculation-state { remaining-value: uint, cumulative-result: uint }))
    (let (
        (applicable-amount (if (> (get remaining-value calculation-state) (get value-threshold tier))
            (- (get remaining-value calculation-state) (get value-threshold tier))
            u0))
        (tier-result (/ (* applicable-amount (get fee-percentage tier)) u100))
    )
        { 
            remaining-value: (get remaining-value calculation-state),
            cumulative-result: (+ (get cumulative-result calculation-state) tier-result)
        }
    )
)

;; Define helper function to update discount approval
(define-private (update-discount-status 
    (index uint) 
    (current-index uint) 
    (discount { discount-code: (string-ascii 10), discount-value: uint, discount-approved: bool })
    (target-index uint))
    (if (is-eq current-index target-index)
        ;; If this is the target index, return updated discount with approved status
        {
            discount-code: (get discount-code discount),
            discount-value: (get discount-value discount),
            discount-approved: true
        }
        ;; Otherwise return the original discount unchanged
        discount)
)

;; Administrative functions - with input validation
(define-public (update-asset-price (asset-symbol (string-ascii 10)) (new-price uint))
    (begin
        ;; Authorization check
        (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-AUTHORIZED)
        ;; Input validation
        (asserts! (is-supported-asset asset-symbol) ERR-UNSUPPORTED-ASSET)
        (asserts! (> new-price u0) ERR-INVALID-AMOUNT)
        
        ;; Now it's safe to update the map
        (ok (map-set asset-prices
            { asset-symbol: asset-symbol }
            { price-value: new-price,
              last-updated: block-height,
              is-active: true }
        ))
    )
)
