;; Document Verification Smart Contract

;; Error codes
(define-constant ERROR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERROR-DUPLICATE-DOCUMENT (err u101))
(define-constant ERROR-DOCUMENT-NOT-FOUND (err u102))
(define-constant ERROR-DOCUMENT-ALREADY-VERIFIED (err u103))
(define-constant ERROR-INVALID-DOCUMENT-IDENTIFIER (err u104))
(define-constant ERROR-INVALID-DOCUMENT-CONTENT (err u105))
(define-constant ERROR-INVALID-DOCUMENT-METADATA (err u106))
(define-constant ERROR-INVALID-VERIFIER (err u107))
(define-constant ERROR-INVALID-PARAMETER (err u108))
(define-constant ERROR-ACCESS-DENIED (err u109))

;; Constants for verification status
(define-constant VERIFICATION-STATUS-PENDING "PENDING")
(define-constant VERIFICATION-STATUS-VERIFIED "VERIFIED")

;; Define document record structure
(define-data-var document-record-structure 
    {
        document-submitter: principal,
        document-hash: (buff 32),
        creation-timestamp: uint,
        current-status: (string-ascii 20),
        verifier-principal: (optional principal),
        additional-metadata: (string-utf8 256),
        current-version: uint,
        is-verification-complete: bool
    }
    {
        document-submitter: tx-sender,
        document-hash: 0x0000000000000000000000000000000000000000000000000000000000000000,
        creation-timestamp: u0,
        current-status: VERIFICATION-STATUS-PENDING,
        verifier-principal: none,
        additional-metadata: u"",
        current-version: u0,
        is-verification-complete: false
    }
)

;; Data maps
(define-map document-storage
    { document-identifier: (buff 32) }
    {
        document-submitter: principal,
        document-hash: (buff 32),
        creation-timestamp: uint,
        current-status: (string-ascii 20),
        verifier-principal: (optional principal),
        additional-metadata: (string-utf8 256),
        current-version: uint,
        is-verification-complete: bool
    }
)

(define-map document-access-control
    { document-identifier: (buff 32), verifier-address: principal }
    { can-view-document: bool, can-verify-document: bool }
)

;; Input validation functions
(define-private (validate-hash-length (hash-input (buff 32)))
    (if (is-eq (len hash-input) u32)
        (ok hash-input)
        ERROR-INVALID-PARAMETER)
)

(define-private (validate-metadata-length (metadata-input (string-utf8 256)))
    (if (and 
            (<= (len metadata-input) u256)
            (> (len metadata-input) u0))
        (ok metadata-input)
        ERROR-INVALID-PARAMETER)
)

(define-private (validate-verifier-address (verifier-address principal))
    (if (and 
            (not (is-eq verifier-address tx-sender))
            (not (is-eq verifier-address (as-contract tx-sender))))
        (ok verifier-address)
        ERROR-INVALID-PARAMETER)
)

;; Enhanced validation functions with consistent response types
(define-private (validate-document-identifier (document-id (buff 32)))
    (validate-hash-length document-id)
)

(define-private (validate-document-metadata (metadata-content (string-utf8 256)))
    (validate-metadata-length metadata-content)
)

(define-private (validate-document-verifier (document-owner principal) (verifier-address principal))
    (if (not (is-eq document-owner verifier-address))
        (ok verifier-address)
        ERROR-INVALID-VERIFIER)
)

;; Safe getter functions
(define-private (get-document-safely (document-id (buff 32)))
    (ok (unwrap! (map-get? document-storage { document-identifier: document-id })
        ERROR-DOCUMENT-NOT-FOUND))
)

;; Read-only functions
(define-read-only (get-document-information (document-id (buff 32)))
    (let ((validated-document-id (try! (validate-document-identifier document-id))))
        (get-document-safely validated-document-id))
)

(define-read-only (get-verifier-permissions (document-id (buff 32)) (verifier-address principal))
    (let (
        (validated-document-id (try! (validate-document-identifier document-id)))
        (validated-verifier (try! (validate-verifier-address verifier-address)))
    )
        (ok (default-to 
            { can-view-document: false, can-verify-document: false }
            (map-get? document-access-control 
                { document-identifier: validated-document-id, verifier-address: validated-verifier })))
    )
)

;; Public functions
(define-public (submit-new-document 
    (document-id (buff 32))
    (document-content-hash (buff 32))
    (document-metadata (string-utf8 256)))
    (let (
        (document-creator tx-sender)
        (validated-document-id (unwrap! (validate-document-identifier document-id) ERROR-INVALID-DOCUMENT-IDENTIFIER))
        (validated-content (unwrap! (validate-document-identifier document-content-hash) ERROR-INVALID-DOCUMENT-CONTENT))
        (validated-metadata (unwrap! (validate-document-metadata document-metadata) ERROR-INVALID-DOCUMENT-METADATA))
    )
        ;; Check for duplicate document
        (asserts! (is-none (map-get? document-storage { document-identifier: validated-document-id }))
            ERROR-DUPLICATE-DOCUMENT)
        
        (ok (map-set document-storage
            { document-identifier: validated-document-id }
            {
                document-submitter: document-creator,
                document-hash: validated-content,
                creation-timestamp: block-height,
                current-status: VERIFICATION-STATUS-PENDING,
                verifier-principal: none,
                additional-metadata: validated-metadata,
                current-version: u1,
                is-verification-complete: false
            }))
    )
)

(define-public (update-existing-document
    (document-id (buff 32))
    (new-content-hash (buff 32))
    (new-metadata (string-utf8 256)))
    (let (
        (validated-document-id (unwrap! (validate-document-identifier document-id) ERROR-INVALID-DOCUMENT-IDENTIFIER))
        (validated-content (unwrap! (validate-document-identifier new-content-hash) ERROR-INVALID-DOCUMENT-CONTENT))
        (validated-metadata (unwrap! (validate-document-metadata new-metadata) ERROR-INVALID-DOCUMENT-METADATA))
        (existing-document (unwrap! (get-document-safely validated-document-id) ERROR-DOCUMENT-NOT-FOUND))
    )
        (asserts! (is-eq (get document-submitter existing-document) tx-sender)
            ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (not (get is-verification-complete existing-document))
            ERROR-DOCUMENT-ALREADY-VERIFIED)
        
        (ok (map-set document-storage
            { document-identifier: validated-document-id }
            (merge existing-document
                {
                    document-hash: validated-content,
                    additional-metadata: validated-metadata,
                    creation-timestamp: block-height,
                    current-version: (+ (get current-version existing-document) u1),
                    is-verification-complete: false
                })))
    )
)

(define-public (verify-document
    (document-id (buff 32)))
    (let (
        (validated-document-id (unwrap! (validate-document-identifier document-id) ERROR-INVALID-DOCUMENT-IDENTIFIER))
        (existing-document (unwrap! (get-document-safely validated-document-id) ERROR-DOCUMENT-NOT-FOUND))
        (verifier-permissions (unwrap! (get-verifier-permissions validated-document-id tx-sender) ERROR-ACCESS-DENIED))
    )
        (asserts! (get can-verify-document verifier-permissions)
            ERROR-UNAUTHORIZED-ACCESS)
        (asserts! (not (get is-verification-complete existing-document))
            ERROR-DOCUMENT-ALREADY-VERIFIED)
        
        (ok (map-set document-storage
            { document-identifier: validated-document-id }
            (merge existing-document
                {
                    current-status: VERIFICATION-STATUS-VERIFIED,
                    verifier-principal: (some tx-sender),
                    is-verification-complete: true
                })))
    )
)

(define-public (grant-document-permissions
    (document-id (buff 32))
    (verifier-address principal)
    (allow-viewing bool)
    (allow-verification bool))
    (let (
        (validated-document-id (unwrap! (validate-document-identifier document-id) ERROR-INVALID-DOCUMENT-IDENTIFIER))
        (validated-verifier (unwrap! (validate-verifier-address verifier-address) ERROR-INVALID-VERIFIER))
        (existing-document (unwrap! (get-document-safely validated-document-id) ERROR-DOCUMENT-NOT-FOUND))
    )
        (asserts! (is-eq (get document-submitter existing-document) tx-sender)
            ERROR-UNAUTHORIZED-ACCESS)
        
        (ok (map-set document-access-control
            { document-identifier: validated-document-id, verifier-address: validated-verifier }
            { 
                can-view-document: allow-viewing, 
                can-verify-document: allow-verification 
            }))
    )
)

(define-public (revoke-document-permissions
    (document-id (buff 32))
    (verifier-address principal))
    (let (
        (validated-document-id (unwrap! (validate-document-identifier document-id) ERROR-INVALID-DOCUMENT-IDENTIFIER))
        (validated-verifier (unwrap! (validate-verifier-address verifier-address) ERROR-INVALID-VERIFIER))
        (existing-document (unwrap! (get-document-safely validated-document-id) ERROR-DOCUMENT-NOT-FOUND))
    )
        (asserts! (is-eq (get document-submitter existing-document) tx-sender)
            ERROR-UNAUTHORIZED-ACCESS)
        
        (ok (map-delete document-access-control
            { document-identifier: validated-document-id, verifier-address: validated-verifier }))
    )
)