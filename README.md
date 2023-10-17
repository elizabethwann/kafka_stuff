# Repository for Kafka Things

## Contents

### eks_offsets
For testing effect of multiple consumers in consumer group on offset commit message
* Spins up EKS cluster using eksctl
* Deploys Kafka using CFK operator
* Deploys Kafka topics, producers and consumers using Helm charts
* Reads from offsets_commit topic

