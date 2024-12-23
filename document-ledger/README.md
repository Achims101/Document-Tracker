# Document Verification Smart Contract

A secure and flexible smart contract for managing document verification on the Stacks blockchain. This contract enables document submission, verification, and permission management with robust security controls.

## Features

- Document submission and storage with version control
- Secure verification process with role-based access
- Granular permission management for document viewing and verification
- Input validation and sanitization
- Comprehensive error handling
- Metadata support for additional document information

## Contract Structure

### Data Structures

#### Document Record
```clarity
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
```

#### Access Control Record
```clarity
{
    can-view-document: bool,
    can-verify-document: bool
}
```

### Public Functions

#### 1. submit-new-document
Registers a new document in the system.
```clarity
(submit-new-document 
    (document-id (buff 32))
    (document-content-hash (buff 32))
    (document-metadata (string-utf8 256)))
```

#### 2. update-existing-document
Updates an existing document before verification.
```clarity
(update-existing-document
    (document-id (buff 32))
    (new-content-hash (buff 32))
    (new-metadata (string-utf8 256)))
```

#### 3. verify-document
Marks a document as verified by an authorized verifier.
```clarity
(verify-document
    (document-id (buff 32)))
```

#### 4. grant-document-permissions
Assigns viewing and verification permissions to a specific address.
```clarity
(grant-document-permissions
    (document-id (buff 32))
    (verifier-address principal)
    (allow-viewing bool)
    (allow-verification bool))
```

#### 5. revoke-document-permissions
Removes all permissions for a specific address.
```clarity
(revoke-document-permissions
    (document-id (buff 32))
    (verifier-address principal))
```

### Read-Only Functions

#### 1. get-document-information
Retrieves detailed information about a document.
```clarity
(get-document-information 
    (document-id (buff 32)))
```

#### 2. get-verifier-permissions
Checks the permissions assigned to a specific address.
```clarity
(get-verifier-permissions 
    (document-id (buff 32))
    (verifier-address principal))
```

## Error Codes

- `ERROR-UNAUTHORIZED-ACCESS (u100)`: User doesn't have required permissions
- `ERROR-DUPLICATE-DOCUMENT (u101)`: Document ID already exists
- `ERROR-DOCUMENT-NOT-FOUND (u102)`: Document doesn't exist
- `ERROR-DOCUMENT-ALREADY-VERIFIED (u103)`: Cannot modify verified document
- `ERROR-INVALID-DOCUMENT-IDENTIFIER (u104)`: Invalid document ID format
- `ERROR-INVALID-DOCUMENT-CONTENT (u105)`: Invalid document content hash
- `ERROR-INVALID-DOCUMENT-METADATA (u106)`: Invalid metadata format
- `ERROR-INVALID-VERIFIER (u107)`: Invalid verifier address
- `ERROR-INVALID-PARAMETER (u108)`: Generic input validation error
- `ERROR-ACCESS-DENIED (u109)`: Permission-related error

## Usage Example

1. Submit a new document:
```clarity
(contract-call? .document-verification submit-new-document
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
    0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
    u"Document title: Contract Agreement")
```

2. Grant verification permissions:
```clarity
(contract-call? .document-verification grant-document-permissions
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
    'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
    true
    true)
```

3. Verify document:
```clarity
(contract-call? .document-verification verify-document
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef)
```

## Security Considerations

1. All document hashes must be 32 bytes long
2. Document owners can only modify documents before verification
3. Only authorized verifiers can verify documents
4. Permission changes require document ownership
5. Input validation is performed on all parameters
6. Document metadata is limited to 256 bytes

## Best Practices

1. Always verify the return value of contract calls
2. Keep document metadata concise and relevant
3. Regularly audit granted permissions
4. Store document content off-chain, only storing hashes on-chain
5. Maintain proper version control for document updates
6. Implement proper error handling in client applications

## Integration Guidelines

1. Generate secure document IDs using cryptographic hash functions
2. Implement proper error handling for all contract calls
3. Validate all inputs before sending to the contract
4. Keep track of document versions in your application
5. Implement proper permission management UI
6. Store additional metadata in a structured format