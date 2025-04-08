# Certificate Verification and Operator Tables

## Overview

At a high level, AVSs are certificate generators. They're protocols that select an evolving set of operators to certify certain statements. These statements could be new block headers of a blockchain or AI inference outputs. 

Certificates are consumed by consumers that want to take actions based off of certified statements without validating them themselves. For example Bridge smart contracts want access to the state of other chains, but it is not scalable for them to validate the state transitions and DA of other chains. Instead, they want certificates of bridge headers.

## CertificateVerifier Contract

As part of this, we introduce a new CertificateVerifier contract, which verifies certificates for a given operatorSet. It is deployed to every chain where the operatorSet's certificates are being consumed. OperatorSets are a grouping of operators who have some stake allocated to an AVS. 

Verifying the certificate requires the certificate being verified, the signature data of the operators that signed the certificate, and maybe some auxiliary data. An operator table is the cryptographic key material of the operatorSet in order to verify the signature and the weight data of the operatorSet in order to verify that "enough" weight has signed off on a statement. 

## Operator Table Maintenance

The operator table is updated at a slow frequency (on the order of days), but its freshness with respect to the time at which it is being used for verification is crucial for security of consumers. Since the set of registered operators and their stake for any given operatorSet changes over time, the operator table of every CertificateVerifier must be still valid to prevent verifiers from accepting certificates against stakes that are no longer slashable. 