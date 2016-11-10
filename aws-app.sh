#!/bin/bash
#### Wave Ops Challenge
####
####

#set -o errexit
#set -o pipefail


virtualenv  -p python2.7 waveansible

source waveansible/bin/activate

pip -q install ansible
pip -q install boto

ansible-vault decrypt  env/secrets.yml --ask-vault-pass

source env/secrets.yml

echo "Starting AWS setup ...."

ansible-playbook --tag aws   playbook.yml 


new_instance_ip=$(aws ec2 describe-instances --filters Name=tag:Name,Values=wsoyinka-waveapp --output text --query 'Reservations[*].Instances[*].PublicIpAddress')


## Forcefully bootstrap 16.04 LTS ami


ssh  -i ./wsoyinka-opseng-challenge-key.pem -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo apt-get -qq -y update && sudo dpkg --configure -a"  


ssh  -i ./wsoyinka-opseng-challenge-key.pem -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo apt-get -qq -y install python2.7"

ssh  -i ./wsoyinka-opseng-challenge-key.pem -o StrictHostKeyChecking=no  ubuntu@$new_instance_ip  "sudo ln  -s /usr/bin/python2.7 /usr/bin/python" 


ansible-playbook --tag common,nginx,deploy   playbook.yml 

ansible-vault encrypt  env/secrets.yml --ask-vault-pass

echo ""
echo ""

clear

echo ""
echo ""

echo  "The website can be reached at:"
echo ""

echo  "http://$new_instance_ip " 

echo ""

echo " Wave Cares About You Financial Records/Data.  PCI DSS compliant version of this high security application is here :-) "

echo ""

echo  "https://$new_instance_ip"

echo ""
echo ""
echo ""
