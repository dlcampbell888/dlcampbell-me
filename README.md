# dlcampbell-me
http://dlcampbell.me

##Prerequistes

###awscli set up and running 
* Default profile in ~/.aws/config
* Access key in the profile with Administrator rights

###AWS resources are available
* VPC and public subnet created
* EC2 key pair called "docker" created and docker.pem available on PATH_TO_DOCKER_KEY
* IAM role for the host instance with S3 access created
* Route53 hosted zone created with your domain name

##Deploying

1. Clone the repo
2. Edit provision.conf to specify your values
3. Run ./provision.sh

Wait for several minutes for the site to start up.

##Files

* destroy.sh - Destroys the site
* functions - AWS wrapper and utility functions
* provision.conf - Site configuration variables
* provision.sh - Creates the site
* README.md - This file
* site/ - A static web root that will be deployed to S3 and loaded by the host
* userdata.txt - User data for host instance that also runs the docker container

##To do

* Add error handling to instance creation
* 
