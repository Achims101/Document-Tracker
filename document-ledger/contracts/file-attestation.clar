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

;; Enhanced validation functions with strict checks
(define-private (validate-hash (hash-input (buff 32)))
    (if (is-eq (len hash-input) u32)
        (ok hash-input)
        ERROR-INVALID-PARAMETER))

(define-private (validate-metadata (metadata-input (string-utf8 256)))
    (if (and (<= (len metadata-input) u256) (> (len metadata-input) u0))
        (ok metadata-input)
        ERROR-INVALID-PARAMETER))

(define-private (validate-verifier (verifier-input principal))
    (if (and 
        (not (is-eq verifier-input tx-sender))
        (not (is-eq verifier-input (as-contract tx-sender))))
        (ok verifier-input)
        ERROR-INVALID-VERIFIER))

;; Safe getter with enhanced error handling
(define-private (get-document-safely (document-id (buff 32)))
    (match (validate-hash document-id)
        validated-id (match (map-get? document-storage { document-identifier: validated-id })
            doc-data (ok doc-data)
            ERROR-DOCUMENT-NOT-FOUND)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))

;; Read-only functions with validation
(define-read-only (get-document-information (document-id (buff 32)))
    (get-document-safely document-id))

(define-read-only (get-verifier-permissions (document-id (buff 32)) (verifier-address principal))
    (match (validate-hash document-id)
        validated-id (match (validate-verifier verifier-address)
            validated-verifier (match (map-get? document-access-control 
                { document-identifier: validated-id, verifier-address: validated-verifier })
                permission-data (ok permission-data)
                (ok { can-view-document: false, can-verify-document: false }))
            error ERROR-INVALID-VERIFIER)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))

;; Public functions with enhanced security
(define-public (submit-new-document 
    (document-id (buff 32))
    (document-content-hash (buff 32))
    (document-metadata (string-utf8 256)))
    (match (validate-hash document-id)
        validated-id (match (validate-hash document-content-hash)
            validated-content (match (validate-metadata document-metadata)
                validated-metadata 
                (match (map-get? document-storage { document-identifier: validated-id })
                    existing-doc ERROR-DUPLICATE-DOCUMENT
                    (ok (map-set document-storage
                        { document-identifier: validated-id }
                        {
                            document-submitter: tx-sender,
                            document-hash: validated-content,
                            creation-timestamp: block-height,
                            current-status: VERIFICATION-STATUS-PENDING,
                            verifier-principal: none,
                            additional-metadata: validated-metadata,
                            current-version: u1,
                            is-verification-complete: false
                        })))
                error ERROR-INVALID-DOCUMENT-METADATA)
            error ERROR-INVALID-DOCUMENT-CONTENT)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))

(define-public (update-existing-document
    (document-id (buff 32))
    (new-content-hash (buff 32))
    (new-metadata (string-utf8 256)))
    (match (validate-hash document-id)
        validated-id 
        (match (get-document-safely validated-id)
            existing-document 
            (match (validate-hash new-content-hash)
                validated-content 
                (match (validate-metadata new-metadata)
                    validated-metadata 
                    (if (is-eq (get document-submitter existing-document) tx-sender)
                        (if (not (get is-verification-complete existing-document))
                            (ok (map-set document-storage
                                { document-identifier: validated-id }
                                (merge existing-document
                                    {
                                        document-hash: validated-content,
                                        additional-metadata: validated-metadata,
                                        creation-timestamp: block-height,
                                        current-version: (+ (get current-version existing-document) u1),
                                        is-verification-complete: false
                                    })))
                            ERROR-DOCUMENT-ALREADY-VERIFIED)
                        ERROR-UNAUTHORIZED-ACCESS)
                    error ERROR-INVALID-DOCUMENT-METADATA)
                error ERROR-INVALID-DOCUMENT-CONTENT)
            error ERROR-DOCUMENT-NOT-FOUND)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))

(define-public (verify-document
    (document-id (buff 32)))
    (match (validate-hash document-id)
        validated-id
        (match (get-document-safely validated-id)
            existing-document 
            (match (get-verifier-permissions validated-id tx-sender)
                permissions 
                (if (get can-verify-document permissions)
                    (if (not (get is-verification-complete existing-document))
                        (ok (map-set document-storage
                            { document-identifier: validated-id }
                            (merge existing-document
                                {
                                    current-status: VERIFICATION-STATUS-VERIFIED,
                                    verifier-principal: (some tx-sender),
                                    is-verification-complete: true
                                })))
                        ERROR-DOCUMENT-ALREADY-VERIFIED)
                    ERROR-UNAUTHORIZED-ACCESS)
                error ERROR-UNAUTHORIZED-ACCESS)
            error ERROR-DOCUMENT-NOT-FOUND)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))

(define-public (grant-document-permissions
    (document-id (buff 32))
    (verifier-address principal)
    (allow-viewing bool)
    (allow-verification bool))
    (match (validate-hash document-id)
        validated-id
        (match (get-document-safely validated-id)
            existing-document 
            (match (validate-verifier verifier-address)
                validated-verifier
                (if (is-eq (get document-submitter existing-document) tx-sender)
                    (ok (map-set document-access-control
                        { document-identifier: validated-id, verifier-address: validated-verifier }
                        { 
                            can-view-document: allow-viewing, 
                            can-verify-document: allow-verification 
                        }))
                    ERROR-UNAUTHORIZED-ACCESS)
                error ERROR-INVALID-VERIFIER)
            error ERROR-DOCUMENT-NOT-FOUND)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))

(define-public (revoke-document-permissions
    (document-id (buff 32))
    (verifier-address principal))
    (match (validate-hash document-id)
        validated-id
        (match (get-document-safely validated-id)
            existing-document 
            (match (validate-verifier verifier-address)
                validated-verifier
                (if (is-eq (get document-submitter existing-document) tx-sender)
                    (ok (map-delete document-access-control
                        { document-identifier: validated-id, verifier-address: validated-verifier }))
                    ERROR-UNAUTHORIZED-ACCESS)
                error ERROR-INVALID-VERIFIER)
            error ERROR-DOCUMENT-NOT-FOUND)
        error ERROR-INVALID-DOCUMENT-IDENTIFIER))