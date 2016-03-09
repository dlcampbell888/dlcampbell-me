#!/bin/bash

#load config
. provision.conf

#load AWS wrapper functions
. functions

echo "Starting provisioning of $SITE_DOMAIN!"

#set up security groups and ingress rules
elb_security_group_id=`create_sg $VPC_ID $ELB_SG_NAME "$ELB_SG_DESC"`
echo "Created New SG: $ELB_SG_NAME ($elb_security_group_id) - $ELB_SG_DESC"

security_group_id=`create_sg $VPC_ID $DOCKER_SG_NAME "$DOCKER_SG_DESC"`
echo "Created New SG: $DOCKER_SG_NAME ($security_group_id) - $DOCKER_SG_DESC"

create_sg_cidr_ingress $elb_security_group_id 80 "0.0.0.0/0"
create_sg_sg_ingress $security_group_id 80 $elb_security_group_id
create_sg_cidr_ingress $security_group_id 22 "$MY_IP"

#Create site artifact for instance
rm -f /tmp/site.tgz
( cd site; tar -zcvf /tmp/site.tgz * )
echo "Creating s3://$S3_BUCKET"
aws s3 mb "s3://$S3_BUCKET"
echo "Deploying site to s3://$S3_BUCKET"
aws s3 cp /tmp/site.tgz "s3://$S3_BUCKET"

#create elb
load_balancer_host=`aws elb create-load-balancer \
	--load-balancer-name $ELB_NAME \
	--listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" \
	--subnets $SUBNET_ID \
	--security-groups $elb_security_group_id \
	--output=text` 
load_balancer_zone_id=`aws elb describe-load-balancers \
	--load-balancer-names $ELB_NAME \
	--query "LoadBalancerDescriptions[*].CanonicalHostedZoneNameID" \
	--output=text`
aws elb configure-health-check \
	--load-balancer-name=$ELB_NAME \
	--health-check Target=HTTP:80/index.html,Interval=10,Timeout=5,UnhealthyThreshold=2,HealthyThreshold=2

#start instance (with user data)
if [ "$USE_AUTOSCALE" == "true" ]
then
	echo "USE_AUTOSCALE is true, so creating autoscaling configuration"
	aws autoscaling create-launch-configuration \
		--launch-configuration-name="$LAUNCH_CONFIG_NAME" \
		--image-id $DOCKER_HOST_AMI_ID \
		--iam-instance-profile $IAM_PROFILE \
		--key-name $KEYPAIR_NAME \
		--security-groups "$security_group_id" \
		--instance-type $DOCKER_HOST_INSTANCE_TYPE \
		--user-data file://userdata.txt \
		--output text
	aws autoscaling create-auto-scaling-group \
		--auto-scaling-group-name "$ASG_NAME" \
		--launch-configuration-name "$LAUNCH_CONFIG_NAME" \
		--min-size 1 \
		--max-size 1 \
		--vpc-zone-identifier $SUBNET_ID \
		--load-balancer-names $ELB_NAME \
		--health-check-type ELB \
		--health-check-grace-period 300
else
	#Creating individual instance and manually registering it to ELB
	instance_id=`aws ec2 run-instances \
		--image-id $DOCKER_HOST_AMI_ID \
		--iam-instance-profile Name=$IAM_PROFILE \
		--key-name $KEYPAIR_NAME \
		--security-group-ids "$security_group_id" \
		--instance-type $DOCKER_HOST_INSTANCE_TYPE \
		--subnet-id $SUBNET_ID \
		--user-data file://userdata.txt \
		--output text | grep INSTANCES | awk -F$'\t' '{ print $8 }'`
	instance_ip=`get_instance_ip $instance_id`
	subnet_id=`get_instance_subnet_id $instance_id`

	echo "New instance: $instance_id"
	echo "New instance IP: $instance_ip"
	echo "New instance subnet ID: $subnet_id"

	aws elb register-instances-with-load-balancer \
		--load-balancer-name $ELB_NAME \
		--instances $instance_id \
		--output=text
fi

#test ELB is up
wait_for_url $load_balancer_host

#set up route53
echo "Pointing $SITE_DOMAIN at $load_balancer_host in DNS."
create_dns_alias $SITE_ZONE_ID $SITE_DOMAIN $load_balancer_zone_id $load_balancer_host

echo "$SITE_DOMAIN should be available soon once the DNS changes take effect!"
echo "Please enter your workstation password so we can flush the DNS cache:"
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder;
#test site is up
wait_for_url $SITE_DOMAIN

#ssh help if we're doing one instance
if [ "$USE_AUTOSCALE" != "true" ]
then
	echo "SSH into machine:"
	echo "ssh -i $KEY_PATH ubuntu@$instance_ip"
fi
