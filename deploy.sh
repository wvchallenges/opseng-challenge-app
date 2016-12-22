#!/bin/bash
# Set -e to exit on any error. -v prints all lines before execution.
set -ev
##########################
### VPC and Subnets ###
## Search for VPC with "vsanjay85" tag
## If found, skip. Else create
vpcid=$(aws ec2 describe-vpcs --filters Name=tag-value,Values="svaranasi" --query Vpcs[].VpcId)
if [ -z $vpcid ]; then
    vpcid=$(aws ec2 create-vpc --cidr-block 10.0.15.0/24 --query 'Vpc.VpcId')
    aws ec2 create-tags --resources $vpcid --tags Key=Name,Value=svaranasi
fi
echo "VPC ID $vpcid"
sed -i "s/<vpcid>/$vpcid/g" group_vars/all
sleep 5

##########################
## Search for pub and pvt subs with "svaranasi" tag and public/private tag
pub_sub1=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=svaranasi,Name=tag:Type,Values=Public' Name=vpc-id,Values="${vpcid}" --query Subnets[].SubnetId)
pvt_sub1=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=svaranasi,Name=tag:Type,Values=Private' Name=vpc-id,Values="${vpcid}" --query Subnets[].SubnetId)

if [ -z $pub_sub1 ] || [ -z $pvt_sub1 ]; then
    #Subnet create
    #Public Subnets X 1 - 64 IPs each [2^6]
    pub_sub1=$(aws ec2 create-subnet --vpc-id $vpcid --cidr-block 10.0.15.0/26 --availability-zone us-east-1d --query 'Subnet.SubnetId')
    #Private Subnets X 1
    pvt_sub1=$(aws ec2 create-subnet --vpc-id $vpcid --cidr-block 10.0.15.64/26 --availability-zone us-east-1d --query 'Subnet.SubnetId')

    #Tag them
    aws ec2 create-tags --resources $pub_sub1 --tags Key=Name,Value=svaranasi
    aws ec2 create-tags --resources $pvt_sub1 --tags Key=Name,Value=svaranasi
fi

echo "Public Subnet#1 $pub_sub1"
echo "Private Subnet#1 $pvt_sub1"
sed -i "s/<pub_sub1>/$pub_sub1/g" group_vars/all
sed -i "s/<pvt_sub1>/$pvt_sub1/g" group_vars/all
################################

#Routing Table
rtb_nonmain=$(aws ec2 describe-route-tables --filters 'Name=tag:Name,Values=svaranasi,Name=tag:Type,Values=Public' Name=vpc-id,Values="${vpcid}" --query RouteTables[].RouteTableId)

if [ -z rtb_non_main ]; then
    #Create non-main route table:
    rtb_nonmain=$(aws ec2 create-route-table --vpc-id $vpcid --query 'RouteTable.RouteTableId')
    #Tag it
    aws ec2 create-tags --resources $rtb_nonmain --tags Key=Name,Value=svaranasi Key=Type,Value=Public
fi
echo "Public route table: $rtb_nonmain"

#Associate with public subnet
echo "Associating public subnets with public route table"
aws ec2 associate-route-table --route-table-id $rtb_nonmain --subnet-id $pub_sub1

#Search for IGW of this VPC
igw=$(aws ec2 describe-internet-gateways --filters 'Name=tag:Name,Values=svaranasi' --query "InternetGateways[?Attachments[?VpcId=='${vpcid}']].InternetGatewayId")

if [ -z $igw ]; then
    #Create internet gateway
    echo "Creating IGW, attaching to VPC and creating route within public route table.."
    igw=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId')
    #Attach to VPC
    aws ec2 attach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcid
    # Tag it
    aws ec2 create-tags --resources $igw --tags Key=Name,Value=svaranasi
fi

#Create routes for public subnet / public routing table. Always returns "True" - immutable operation. Never returns error.
aws ec2 create-route --route-table-id $rtb_nonmain --destination-cidr-block 0.0.0.0/0 --gateway-id $igw

echo "Internet Gateway: $igw"

nat_gw=$(aws ec2 describe-nat-gateways --nat-gateway-ids $nat_gw --query "NatGateways[?SubnetId=='$pub_sub1'].NatGatewayId")
if [ -z $nat_gw ]; then
    #Create NAT gateway, but first create new EIP
    echo "Creating EIP, NAT Gateway and their association.."
    eip_4nat=$(aws ec2 allocate-address --domain vpc --query 'AllocationId')
    nat_gw=$(aws ec2 create-nat-gateway --subnet-id $pub_sub1 --allocation-id $eip_4nat --query 'NatGateway.NatGatewayId')
    #Wait for NAT or else it won't let you attach routes to it
    state="pending"
    while [ $state == "pending" ]; do	
	echo "Waiting for NAT GW to be available.."
	sleep 10
	state=$(aws ec2 describe-nat-gateways --nat-gateway-ids $nat_gw --query 'NatGateways[].State')
    done
fi
echo "NatGateway: $nat_gw" 

#Create routes for private subnet / main route table - no association needed.
#First find main route table:
rtb_main=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$vpcid Name=association.main,Values=true --query 'RouteTables[].RouteTableId')
#Then create route to nat-gateway (returns True)
tmp==$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$vpcid Name=association.main,Values=true)
if ! [[ "$tmp" == *"$nat_gw"* ]]; then
    echo "Creating route to NAT GW from private subnets.."
    aws ec2 create-route --route-table-id $rtb_main --nat-gateway-id $nat_gw --destination-cidr-block 0.0.0.0/0
    ### END VPC and Subnets ###
else
   echo "Private subnet route to NAT GW exists"
fi

################################################################################
ansible-playbook 011_create_bastion.yml

# ec2_pub.py is set to look at public IP addresses. let's refresh it.
./ec2_pub.py --refresh > /dev/null
bastion_ip=$(ansible -i ec2_pub.py tag_Name_svaranasi_bastion_instance --list-hosts | awk '{print $1}' | sed 's/hosts//g' | tr -d '\n')
sed -i "s/<bastion-string>/ec2-user@$bastion_ip/g" group_vars/all
echo $bastion_ip
ssh-keyscan -H $bastion_ip >> ~/.ssh/known_hosts

# ec2.py is set to look at internal IP addresses. let's refresh it.
## Switch to using private IPs ##
./ec2.py --refresh > /dev/null
ansible-playbook 012_create_pvt_instance.yml
ansible-playbook 013_create_elb.yml

#Register the instance with the ELB. Easier with AWS CLI than Ansible.

iid=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=svaranasi_private_instance" --query 'Reservations[].Instances[].InstanceId')
echo "Registering Instance ${iid} with ELB"
aws elb register-instances-with-load-balancer --load-balancer-name svaranasi-lb --instances $iid

ansible-playbook -i ec2.py 021_app_install.yml

################################################################################
################################################################################

### EC2, ELB, ASG and LC configuration ###
#Create Launch Config
#Create LC security group (a.k.a private SG)
#echo "Creating Launch Config SG, Launch Config"
#pvt_sg=$(aws ec2 describe-security-groups --filters 'Name=group-name,Values="svaranasi_pvt_sg"' Name=vpc-id,Values="${vpcid}" --query SecurityGroups[].GroupId)
#if [ -z $pvt_sg ]; then
#    pvt_sg=$(aws ec2 create-security-group --vpc-id $vpcid --group-name svaranasi_pvt_sg --description "SG for Private Subnets" --query 'GroupId')
#fi
#echo "Private SG: $pvt_sg"

#Create ELB security group
#echo "Creating ELB SG, ELB, and defining Health Check on TCP 80.."
#elb_sg=$(aws ec2 describe-security-groups --filters 'Name=group-name,Values="svaranasi_elb_sg"' Name=vpc-id,Values="${vpcid}" --query SecurityGroups[].GroupId)
#if [ -z $elb_sg ]; then 
#    elb_sg=$(aws ec2 create-security-group --vpc-id $vpcid --group-name svaranasi_elb_sg --description "Public ELB for the application" --query 'GroupId')
#fi

#app_dns=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[?LoadBalancerName==`svaranasi-lb`].DNSName')
#if ! [[ "$app_dns" == *"svaranasi"* ]]; then
    #Create ELB
#    app_dns=$(aws elb create-load-balancer --load-balancer-name svaranasi-lb --listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" --subnets $pub_sub1 --security-groups $elb_sg --query 'DNSName')
    # Enable Health Check on TCP 80
#    aws elb configure-health-check --load-balancer-name svaranasi-lb --health-check Target=TCP:80,Interval=45,UnhealthyThreshold=3,HealthyThreshold=10,Timeout=5
#fi

#kp=$(aws ec2 describe-key-pairs --query 'KeyPairs[?KeyName==`svaranasi-kp`].KeyName')
#if ! [ "$kp" == "svaranasi-kp" ]; then
#    # Create KP
#    aws ec2 create-key-pair --keyname svaranasi-kp
#fi

################################################################################################################
#Setup Bastion
#Create Bastion SG
#echo "Creating Bastion SG and Bastion instance.."
#bstn_sg=$(aws ec2 create-security-group --vpc-id $vpcid --group-name deploy-test-bastion --description "Deploy-Test-Bastion" --query 'GroupId')
#Run instance
#aws ec2 run-instances --image-id ami-002f0f6a --key-name "svaranasi-kp" --security-group-ids $bstn_sg --instance-type t2.micro --block-device-mappings "[{\"DeviceName\": \"/dev/sda1\",\"Ebs\":{\"VolumeSize\":8}}]" --subnet-id $pub_sub1 --no-ebs-optimized --associate-public-ip-address


#Security Groups Provisioning
#To PVT SG From ELB
#echo "Defining subnet groups inbound/outbound rules.."
#aws ec2 authorize-security-group-ingress --group-id $pvt_sg --protocol tcp --port 22 --source-group $elb_sg
#aws ec2 authorize-security-group-ingress --group-id $pvt_sg --protocol tcp --port 80 --source-group $elb_sg
#To PVT SG From Self
#aws ec2 authorize-security-group-ingress --group-id $pvt_sg --protocol all --source-group $pvt_sg
#To PVT SG From Bastion
#aws ec2 authorize-security-group-ingress --group-id $pvt_sg --protocol tcp --port 22 --source-group $bstn_sg
#aws ec2 authorize-security-group-ingress --group-id $pvt_sg --protocol icmp --port -1 --source-group $bstn_sg

# Get public IP of this machine to allow sec_grp access.
#this_ip=$(curl http://ipecho.net/plain)

#To ELB from world
#aws ec2 authorize-security-group-ingress --group-id $elb_sg --protocol tcp --port 80 --cidr "${ip}/32"
#To bastion from world
#aws ec2 authorize-security-group-ingress --group-id $bstn_sg --protocol tcp --port 22 --cidr "${ip}/32"

#From Bastion to PVT SG
#aws ec2 authorize-security-group-egress --group-id $bstn_sg --protocol tcp --port 22 --source-group $pvt_sg
#aws ec2 authorize-security-group-egress --group-id $bstn_sg --protocol icmp --port -1 --source-group $pvt_sg

#From ELB to PVT SG
#aws ec2 authorize-security-group-egress --group-id $elb_sg --protocol tcp --port 80 --source-group $pvt_sg

#echo "The app will be available shortly on $app_dns"
### END SCRIPT ###
