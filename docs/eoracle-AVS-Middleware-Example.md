## eoracle AVS Middleware Example 
The following is an example of how eoracle leverages Eigenlayer integration with the middleware package to actively validate oracle operations. 


Eigenlayer operators are permissioned to register through the eoracle middleware , which forward information to the eoracle chain manager. Through a dedicated bridging contract, their Eigenlayer shares are forwarded to the eoracle chain, where they provide cryptographic trust and validation to oracle operations.  

[Documentation](https://eoracle.gitbook.io/eoracle/)

[eoracle middleware source code](https://github.com/Eoracle/eoracle-middleware/)

```mermaid 
flowchart LR
    OP[Eigenlayer Operators]
    subgraph Ethereum
        Dapp1[Dapp 1 Contract]
        subgraph Oracle AVS Contracts
            subgraph Registration Contracts
                RegistryCoordinator
                ServiceManager
            end
            OracleInterface
        end
        ETHBridgingContract[Bridge]
        subgraph Eigenlayer Contracts
            DM[Delegation Manager]
            SM[StrategyManager]
            AVSD[AVSDirectory]
        end
    end
    subgraph Oracle AVS Chain
        AggregatorContract
        OracleChainBridgingContract[Bridge]
    end
    subgraph Oracle AVS Node Cluster
        ON1[Oracle Eigenlayer Operator 1]
        ON2[Oracle Eigenlayer Operator 2]
        ON3[Oracle Eigenlayer Operator 3]
    end
    ON1 --> |Report Price Feed Data | AggregatorContract
    ON2 --> |Report Price Feed Data | AggregatorContract
    ON3 --> |Report Price Feed Data | AggregatorContract
    OP --> |Register |RegistryCoordinator
    RegistryCoordinator  --> |Read Operator Data| DM
    RegistryCoordinator  -->|Read Operator Data| SM
    ServiceManager --> |Write Operator Registrations| AVSD
    ServiceManager -->|Update Operator Information| ETHBridgingContract 
    RegistryCoordinator ---> ServiceManager
    ETHBridgingContract --> |Send Latest Price Feed Data  |OracleInterface
    ETHBridgingContract<---> |Relay messages| OracleChainBridgingContract
    AggregatorContract --> |Send Latest Price Feed Data| OracleChainBridgingContract
    OracleChainBridgingContract --> |Recieve Operator Information|AggregatorContract
    Dapp1 --> |Consume Price Feed |OracleInterface
    OracleInterface --> |Verify Threshold Signatures| OracleInterface
```

```mermaid 
sequenceDiagram

box Ethereum AVS Contracts

participant Operator

participant RegistryCoordinator

participant IndexRegistry

participant StakeRegistry

participant BLSApkRegistry

participant ChainManager

participant StateSender

end

box Ethereum Eigenlayer Contracts

participant DelegationManager

participant StrategyManager

participant AVS Directory

end

box eoracle Chain Contracts

participant StateReciever

participant Aggregator

end

Operator->>RegistryCoordinator: registerAsOperator

RegistryCoordinator ->>StakeRegistry : Register Stake

StakeRegistry ->> DelegationManager : Fetch Delegated Stake

DelegationManager ->> StrategyManager: Fetch Total Stake for Operator

RegistryCoordinator ->>IndexRegistry : Update Operator Set

RegistryCoordinator ->>BLSApkRegistry : Update Operator Set BLS Aggregate Public Key

RegistryCoordinator ->>ChainManager : Forward Operator Shares, BLS Public Key and ECDSA Address

ChainManager ->> StateSender : Send Message to Chain

StateSender ->> StateReciever : Message is bridged via a message signed by the current operator set

StateReciever ->> Aggregator : Update operator permissions and stake
```