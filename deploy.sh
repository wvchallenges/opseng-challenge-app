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
sed -i "s/<vpcid>/$vpcid/g" group_vars/all.yml
sleep 5

##########################
## Search for pub and pvt subs with "svaranasi" tag and public/private tag
pub_sub1=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=svaranasi,Name=tag:Type,Values=Public' Name=vpc-id,Values="${vpcid}" --query Subnets[].SubnetId)
pvt_sub1=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=svaranasi,Name=tag:Type,Values=Private' Name=vpc-id,Values="${vpcid}" --query Subnets[].SubnetId)

if [ -z $pub_sub1 ]; then
    #Public Subnets X 1 - 64 IPs each [2^6]
    pub_sub1=$(aws ec2 create-subnet --vpc-id $vpcid --cidr-block 10.0.15.0/26 --availability-zone us-east-1d --query 'Subnet.SubnetId')
fi
if [ -z $pvt_sub1 ]; then
    #Private Subnets X 1
    pvt_sub1=$(aws ec2 create-subnet --vpc-id $vpcid --cidr-block 10.0.15.64/26 --availability-zone us-east-1d --query 'Subnet.SubnetId')
fi
#Tag them
aws ec2 create-tags --resources $pub_sub1 --tags Key=Name,Value=svaranasi Key=Type,Value=Public
aws ec2 create-tags --resources $pvt_sub1 --tags Key=Name,Value=svaranasi Key=Type,Value=Private

echo "Public Subnet#1 $pub_sub1"
echo "Private Subnet#1 $pvt_sub1"
sed -i "s/<pub_sub1>/$pub_sub1/g" group_vars/all.yml
sed -i "s/<pvt_sub1>/$pvt_sub1/g" group_vars/all.yml
################################

#Routing Table
rtb_nonmain=$(aws ec2 describe-route-tables --filters 'Name=tag:Name,Values=svaranasi,Name=tag:Type,Values=Public' Name=vpc-id,Values="${vpcid}" --query RouteTables[].RouteTableId)

if [ -z $rtb_nonmain ]; then
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
sed -i "s/<bastion-string>/ec2-user@$bastion_ip/g" group_vars/all.yml
echo $bastion_ip
ssh-keyscan -H $bastion_ip >> ~/.ssh/known_hosts

# ec2.py is set to look at internal IP addresses. let's refresh it.
## Switch to using private IPs ##
./ec2.py --refresh > /dev/null
ansible-playbook 012_create_elb.yml
ansible-playbook 013_create_pvt_instance.yml

#Register the instance with the ELB. Easier with AWS CLI than Ansible.

iid=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=svaranasi_private_instance" --query 'Reservations[].Instances[].InstanceId')
echo "Registering Instance ${iid} with ELB"
aws elb register-instances-with-load-balancer --load-balancer-name svaranasi-lb --instances $iid

ansible-playbook -i ec2.py 021_app_install.yml

################################################################################
################################################################################
### END SCRIPT ###
