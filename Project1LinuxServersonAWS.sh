#!/bin/sh

cidrBlock=10.0.0.0/24
region=us-east-1
declare -A defaultTag
defaultTag='[{Key=project,Value=wecloud}]'
profile=default
ami_id=ami-0aa2b7722dc1b5612
micro=t2.micro
small=t2.small
keyNameForSsh=default

vpc=$(aws ec2 create-vpc --cidr-block ${cidrBlock} --no-amazon-provided-ipv6-cidr-block --region ${region} --tag-specifications 'ResourceType=vpc,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=wecloud}]' --profile ${profile})

vpc_id=$(echo "$vpc" | jq -r '.Vpc.VpcId')

subnet=$(aws ec2 create-subnet --vpc-id ${vpc_id} --cidr-block ${cidrBlock} --availability-zone ${region}a --tag-specifications 'ResourceType=subnet,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=wecloud}]')

subnet_id=$(echo "$subnet" | jq -r '.Subnet.SubnetId')


aws ec2 modify-subnet-attribute --subnet-id ${subnet_id} --map-public-ip-on-launch

internet_gateway=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=wecloud}]')

internet_gateway_id=$(echo "$internet_gateway" | jq -r '.InternetGateway.InternetGatewayId')

aws ec2 attach-internet-gateway --internet-gateway-id ${internet_gateway_id} --vpc-id ${vpc_id}

route_table=$(aws ec2 create-route-table --vpc-id ${vpc_id} --tag-specifications 'ResourceType=route-table,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=wecloud}]')

route_table_id=$(echo "$route_table" | jq -r '.RouteTable.RouteTableId')

aws ec2 create-route --route-table-id ${route_table_id} --destination-cidr-block 0.0.0.0/0 --gateway-id ${internet_gateway_id}

aws ec2 associate-route-table --subnet-id ${subnet_id} --route-table-id ${route_table_id}

role=$(aws iam create-role --role-name ssmmRole --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}')
attach=$(aws iam attach-role-policy --role-name ssmmRole --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore)

ec2_worker_one=$(aws ec2 run-instances --image-id ${ami_id} --count 1 --instance-type ${micro} --key-name ${keyNameForSsh} --subnet-id ${subnet_id} --associate-public-ip-address --tag-specifications 'ResourceType=instance,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=worker-node-01}]')

ec2_worker_two=$(aws ec2 run-instances --image-id ${ami_id} --count 1 --instance-type ${micro} --key-name ${keyNameForSsh} --subnet-id ${subnet_id} --associate-public-ip-address --tag-specifications 'ResourceType=instance,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=worker-node-02}]')

ec2_master_one=$(aws ec2 run-instances --image-id ${ami_id} --count 1 --instance-type ${small} --key-name ${keyNameForSsh} --subnet-id ${subnet_id} --associate-public-ip-address --tag-specifications 'ResourceType=instance,Tags=[{Key=project,Value=wecloud},{Key=Name,Value=master-node-01}]')

ec2_worker_two_instance_id=$(echo "$ec2_worker_two" | jq -r '.Instances[0].InstanceId')
ec2_worker_one_instance_id=$(echo "$ec2_worker_one" | jq -r '.Instances[0].InstanceId')
ec2_master_one_instance_id=$(echo "$ec2_master_one" | jq -r '.Instances[0].InstanceId')

aws ec2 describe-instances --instance-ids ${ec2_worker_two_instance_id} --query 'Reservations[*].Instances[*].IamInstanceProfile'
aws ec2 describe-instances --instance-ids ${ec2_worker_one_instance_id} --query 'Reservations[*].Instances[*].IamInstanceProfile'
# aws ec2 describe-instances --instance-ids ${ec2_master_one_instance_id} --query 'Reservations[*].Instances[*].IamInstanceProfile'

aws iam create-instance-profile --instance-profile-name ec2_worker_two
aws iam create-instance-profile --instance-profile-name ec2_worker_one
# aws iam create-instance-profile --instance-profile-name ec2_master_one

instanceStateOutputInstanceTwo=$(aws ec2 describe-instance-status --instance-ids ${ec2_worker_two_instance_id})
ec2_worker_two_status=$(echo "$instanceStateOutputInstanceTwo" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
while [ "$ec2_worker_two_status" = "null"  ]; do
    echo "Waiting... for instance ${ec2_worker_two_instance_id} to start"
    sleep 5
    instanceStateOutputInstanceTwo=$(aws ec2 describe-instance-status --instance-ids ${ec2_worker_two_instance_id})
    ec2_worker_two_status=$(echo "$instanceStateOutputInstanceTwo" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
done

instanceStateOutputInstanceOne=$(aws ec2 describe-instance-status --instance-ids ${ec2_worker_one_instance_id})
ec2_worker_one_status=$(echo "$instanceStateOutputInstanceOne" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
while [ "$ec2_worker_two_status" = "null"  ]; do
    echo "Waiting... for instance ${ec2_worker_one_instance_id} to start"
    sleep 5
    instanceStateOutputInstanceOne=$(aws ec2 describe-instance-status --instance-ids ${ec2_worker_one_instance_id})
    ec2_worker_one_status=$(echo "$instanceStateOutputInstanceOne" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
done

instanceStateOutputInstanceMaster=$(aws ec2 describe-instance-status --instance-ids ${ec2_master_one_instance_id})
ec2_master_status=$(echo "$instanceStateOutputInstanceMaster" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
while [ "$ec2_worker_two_status" = "null"  ]; do
    echo "Waiting... for instance ${ec2_master_one_instance_id} to start"
    sleep 5
    instanceStateOutputInstanceMaster=$(aws ec2 describe-instance-status --instance-ids ${ec2_master_one_instance_id})
    ec2_master_status=$(echo "$instanceStateOutputInstanceMaster" | jq -r '.InstanceStatuses[0].InstanceStatus.Status')
done

aws iam add-role-to-instance-profile --instance-profile-name ec2_worker_two --role-name ssmmRole
aws iam add-role-to-instance-profile --instance-profile-name ec2_worker_one --role-name ssmmRole
aws iam add-role-to-instance-profile --instance-profile-name ec2_master_one --role-name ssmmRole

aws ec2 associate-iam-instance-profile --instance-id ${ec2_worker_two_instance_id} --iam-instance-profile Name=ec2_worker_two
aws ec2 associate-iam-instance-profile --instance-id ${ec2_worker_one_instance_id} --iam-instance-profile Name=ec2_worker_one
aws ec2 associate-iam-instance-profile --instance-id ${ec2_master_one_instance_id} --iam-instance-profile Name=ec2_master_one

aws ssm create-document --name "DocumentInstallSoft" --content file://softInstall.json --document-type "Command"


command_ec2_worker_two=$(aws ssm send-command --instance-ids ${ec2_worker_two_instance_id} --document-name "DocumentInstallSoft")
command_ec2_worker_one=$(aws ssm send-command --instance-ids ${ec2_worker_one_instance_id} --document-name "DocumentInstallSoft")
command_ec2_master=$(aws ssm send-command --instance-ids ${ec2_master_one_instance_id} --document-name "DocumentInstallSoft")




