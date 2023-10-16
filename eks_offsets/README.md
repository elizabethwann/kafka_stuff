# What Am I

* Deploy EKS Cluster for CFK (Confluent for Kafka)
* Helm Charts to deploy Kafka Topics, Producers and Consumers at scale
* Read from offsets topic to see effect of topics and consumers in consumer group

# Instructions

## Check AWS IAM profile
`aws sts get-caller-identity`

## Create EKS Cluster
`eksctl create cluster --name my-cluster --region region-code`

*Note can't use Fargate as it doesn't allow for PVC*

### [Add EBS CSI driver as EKS addon](https://docs.aws.amazon.com/eks/latest/userguide/managing-ebs-csi.html)

* [Create IAM OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

Get OIDC Issuer ID for cluster:
`oidc_id=$(aws eks describe-cluster --name $cluster_name --query "cluster.identity.oidc.issuer" --region $region --output text | cut -d '/' -f 5)`

Check if IAM OIDC provider for cluster is already present:
`aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4`

If not, create IAM OIDC provider:
`eksctl utils associate-iam-oidc-provider --cluster $cluster_name --approve --region $region`


* [Create the Amazon EBS CSI driver IAM role](https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html)
```
eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster $cluster_name \
    --role-name $rolenameAmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve \
    --region $region
```

`eksctl create addon --name aws-ebs-csi-driver --cluster $my-cluster --service-account-role-arn arn:aws:iam::111122223333:role/$AmazonEKS_EBS_CSI_DriverRole --force --region $eu-west-2`

## Confluent Namespace

`kubectl create namespace confluent`

`kubectl config set-context --current --namespace confluent`

## Deploy CFK

`helm repo add confluentinc https://packages.confluent.io/`

`helm repo update`

`helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes --set kRaftEnabled=true`

## Install CP

`kubectl create -f cp.yaml`

## Helm Charts

Use Helm to deploy Kafka Topics, Producers and Consumers

`helm install topics helm/topics`

`helm install produce helm/produce`

`helm install consume helm/consume`

## Check consumers and offset topic

```
kafka-console-consumer \
  --from-beginning \
  --topic test-topic-0 \
  --bootstrap-server kafka.confluent.svc.cluster.local:9071 
```

```
kafka-console-consumer \
  --from-beginning \
  --topic __consumer_offsets \
  --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
  --formatter \
  "kafka.coordinator.group.GroupMetadataManager\$GroupMetadataMessageFormatter"
```

```
kafka-console-consumer \
  --from-beginning \
  --topic __consumer_offsets \
  --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
  --formatter \
  "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter"
```

# Clean Up

## Helm
`helm uninstall topics`
`helm uninstall produce`
`helm uninstall consume`

## Delete CP
`kubectl delete -f cp.yaml`

## Scaledown EKS Cluster
`eks eksctl scale nodegroup --name ng-7016740c --cluster lizzie --nodes 0 --nodes-min 0 --nodes-max 20 --region eu-west-2`

## Delete EKS Cluster
`eksctl delete cluster --name lizzie --region eu-west-2`