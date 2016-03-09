#!/bin/bash

#load config
. provision.conf

if [ "$USE_AUTOSCALE" != "true" ]
then
	if [ "$1" == "" ]
	then
  		echo "Specify instance id as parameter (e.g. $0 i-7fb905fc)"
 	 	exit 1
	fi
fi

#destroy
echo "Removing bucket $S3_BUCKET"
aws s3 rb --force "s3://$S3_BUCKET"

if [ "$USE_AUTOSCALE" == "true" ]
then
	echo "Setting autoscaling group to 0"
	aws autoscaling update-auto-scaling-group \
		--auto-scaling-group-name "$ASG_NAME" \
		--min-size 0 \
		--max-size 0
	sleep 5
	echo "Deleting autoscaling group"
	aws autoscaling delete-auto-scaling-group \
		--auto-scaling-group-name "$ASG_NAME" \
		--force-delete
	sleep 5
	echo "Deleting launch configuration"
	aws autoscaling delete-launch-configuration \
		--launch-configuration-name="$LAUNCH_CONFIG_NAME"
else
	echo "Terminating instance: $1"
	aws ec2 terminate-instances --instance-ids $1
	sleep 10
fi

echo "Deleting ELB: $ELB_NAME"
aws elb delete-load-balancer --load-balancer-name $ELB_NAME
echo "Deleting security groups"

test=1
while [ $test -ne 0 ]
do
	echo "Attempting to delete $DOCKER_SG_NAME"
	aws ec2 delete-security-group \
		--group-id `aws ec2 describe-security-groups \
		--filters Name=vpc-id,Values=$VPC_ID \
		--filters Name=group-name,Values=$DOCKER_SG_NAME \
		--output text | grep SECURITYGROUPS | awk -F$'\t' '{print $3}'`
	test="$?"
	sleep 10
done

test=1
while [ $test -ne 0 ]
do
	echo "Attempting to delete $ELB_SG_NAME"
	aws ec2 delete-security-group \
		--group-id `aws ec2 describe-security-groups \
		--filters Name=vpc-id,Values=$VPC_ID \
		--filters Name=group-name,Values=$ELB_SG_NAME \
		--output text | grep SECURITYGROUPS | awk -F$'\t' '{print $3}'`
	test="$?"
	sleep 10
done
